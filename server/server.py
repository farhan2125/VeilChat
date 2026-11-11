import socket
import threading
import json
import os
import time
import traceback
from typing import Dict, Optional, List
import bcrypt

HOST = os.environ.get('VEILCHAT_HOST', '0.0.0.0')  # nosec B104
PORT = int(os.environ.get('VEILCHAT_PORT', 5000))
USERS_FILE = 'server_users.json'
OFFLINE_FILE = 'server_offline.json'
GROUPS_FILE = 'server_groups.json'
PROFILES_FILE = 'server_profiles.json'

lock = threading.Lock()
file_lock = threading.Lock()
online_users: Dict[str, socket.socket] = {}


def load_json(fn):
    with file_lock:
        if not os.path.exists(fn):
            return {}
        try:
            with open(fn, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception:
            return {}


def save_json(fn, data):
    with file_lock:
        # Atomic write: write to temp file then replace atomically
        tmp = f"{fn}.tmp_{os.getpid()}_{threading.get_ident()}_{int(time.time()*1000)}"
        try:
            with open(tmp, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            os.replace(tmp, fn)
        except Exception as e:
            if os.path.exists(tmp):
                try:
                    os.remove(tmp)
                except OSError:
                    pass
            raise e


def hash_password(p):
    return bcrypt.hashpw(p.encode(), bcrypt.gensalt(rounds=12)).decode()


def verify_password(p, h):
    try:
        return bcrypt.checkpw(p.encode(), h.encode())
    except Exception:
        return False


def save_user(u, p):
    if len(u) < 3:
        return False, 'Username too short (min 3 chars)'
    # Hash password outside lock so CPU-bound bcrypt doesn't bottleneck other threads
    hashed = hash_password(p)
    with lock:
        users = load_json(USERS_FILE)
        if u in users:
            return False, 'Username already taken'
        users[u] = hashed
        save_json(USERS_FILE, users)
        return True, 'OK'


def verify_user(u, p):
    users = load_json(USERS_FILE)
    h = users.get(u)
    return bool(h and verify_password(p, h))


def queue_offline(target, t, data):
    with lock:
        all_ = load_json(OFFLINE_FILE)
        all_.setdefault(target, [])
        data['type'] = t
        data['timestamp'] = int(time.time() * 1000)
        all_[target].append(data)
        if len(all_[target]) > 200:
            all_[target] = all_[target][-200:]
        save_json(OFFLINE_FILE, all_)


def deliver_offline(sock, username):
    with lock:
        all_ = load_json(OFFLINE_FILE)
        msgs = all_.pop(username, [])
        if msgs:
            save_json(OFFLINE_FILE, all_)
    if not msgs:
        return
    print(f'[DELIVERY] {len(msgs)} offline msgs -> {username}')
    for m in msgs:
        t = m.pop('type', 'TEXT')
        try:
            send_packet(sock, t, m)
            time.sleep(0.05)
        except Exception:
            break


def create_group(gid, name, owner, members):
    g = {'id': gid, 'name': name, 'owner': owner, 'members': members, 'created_at': int(time.time() * 1000)}
    with lock:
        gs = load_json(GROUPS_FILE)
        gs[gid] = g
        save_json(GROUPS_FILE, gs)
    return g


def get_group(gid):
    return load_json(GROUPS_FILE).get(gid)


def safe_recv(sock, size, timeout=120):
    sock.settimeout(timeout)
    data = b''
    try:
        while len(data) < size:
            chunk = sock.recv(size - len(data))
            if not chunk:
                return None
            data += chunk
        return data
    except Exception:
        return None
    finally:
        sock.settimeout(None)


def send_packet(sock, t, d):
    try:
        b = json.dumps(d, ensure_ascii=False).encode()
        sock.sendall(t.ljust(10)[:10].encode() + str(len(b)).ljust(10)[:10].encode() + b)
    except BrokenPipeError:
        pass
    except Exception as e:
        print(f'[SEND ERR] {e}')


def handle_client(conn, addr):
    conn.settimeout(120)
    user = None
    print(f'[+] {addr}')
    try:
        while True:
            hdr = safe_recv(conn, 20)
            if not hdr:
                break
            try:
                t = hdr[:10].decode().strip()
                ln = int(hdr[10:].decode().strip())
                raw = safe_recv(conn, ln)
                if not raw:
                    break
                d = json.loads(raw.decode())
            except Exception as e:
                print(f'[PKT ERR] {e}')
                continue

            try:
                if t == 'REGISTER':
                    ok, msg = save_user(d.get('username', '').strip(), d.get('password', ''))
                    send_packet(conn, 'AUTH_RES', {'status': 'SUCCESS' if ok else 'FAIL', 'msg': msg})

                elif t == 'LOGIN':
                    u = d.get('username', '').strip()
                    if verify_user(u, d.get('password', '')):
                        user = u
                        with lock:
                            old = online_users.get(user)
                            if old and old is not conn:
                                try:
                                    old.close()
                                except (OSError, socket.error):
                                    pass
                            online_users[user] = conn
                        print(f'[AUTH] {user}')
                        send_packet(conn, 'AUTH_RES', {'status': 'SUCCESS', 'msg': f'Welcome {user}!'})
                        deliver_offline(conn, user)
                        # Send groups immediately
                        gs = load_json(GROUPS_FILE)
                        ug = [g for g in gs.values() if user in g['members']]
                        if ug:
                            send_packet(conn, 'GRPS_LIST', {'groups': ug})
                    else:
                        send_packet(conn, 'AUTH_RES', {'status': 'FAIL', 'msg': 'Invalid username or password'})

                elif t == 'PING':
                    send_packet(conn, 'PONG', {'ts': int(time.time() * 1000)})

                elif t == 'GET_USERS':
                    if not user:
                        continue
                    all_u = list(load_json(USERS_FILE).keys())
                    profiles = load_json(PROFILES_FILE)
                    user_data = {}
                    for u in all_u:
                        if u == user:
                            continue
                        status = 'Online' if u in online_users else 'Offline'
                        ls = profiles.get(u, {}).get('lastSeen', 0)
                        user_data[u] = {'status': status, 'lastSeen': ls}
                    send_packet(conn, 'USER_LIST', {'users': user_data})

                elif t == 'GET_USER_LIST':
                    if not user:
                        continue
                    all_u = load_json(USERS_FILE)
                    profiles = load_json(PROFILES_FILE)
                    user_data = {}
                    for u in all_u:
                        if u == user:
                            continue
                        status = 'Online' if u in online_users else 'Offline'
                        ls = profiles.get(u, {}).get('lastSeen', 0)
                        user_data[u] = {'status': status, 'lastSeen': ls}
                    send_packet(conn, 'USER_LIST', {'users': user_data})

                elif t in ('TEXT', 'IMAGE', 'AUDIO', 'FILE', 'TYPING', 'READ_RECEI', 'DELIVERED_', 'OFFER', 'ANSWER', 'ICE', 'END', 'DELETE_MSG'):
                    if not user:
                        continue
                    d['sender'] = user
                    tgt = d.get('to_user')
                    if not tgt:
                        continue
                    with lock:
                        ts = online_users.get(tgt)
                    if ts:
                        send_packet(ts, t, d)
                    elif t in ('TEXT', 'IMAGE', 'AUDIO', 'FILE'):
                        queue_offline(tgt, t, d)

                elif t == 'PROFILE_UPDATE':
                    if user:
                        with lock:
                            curr_profiles = load_json(PROFILES_FILE)
                            curr_profiles[user] = d.get('profile', {})
                            save_json(PROFILES_FILE, curr_profiles)

                elif t == 'GET_PROFILE':
                    tgt = d.get('username')
                    if tgt:
                        send_packet(conn, 'PROFILE_DATA', {'username': tgt, 'profile': load_json(PROFILES_FILE).get(tgt, {})})

                elif t == 'NEW_GROUP':
                    if not user:
                        continue
                    gid = f"grp_{int(time.time()*1000)}_{user}"
                    name = d.get('name', 'Group')
                    members = d.get('members', [])
                    if user not in members:
                        members.append(user)
                    g = create_group(gid, name, user, members)
                    send_packet(conn, 'GRP_NEW', {'groupId': gid, 'name': name, 'owner': user, 'members': members, 'timestamp': g['created_at']})
                    for m in members:
                        if m == user:
                            continue
                        inv = {'groupId': gid, 'name': name, 'owner': user, 'members': members, 'inviter': user}
                        with lock:
                            s = online_users.get(m)
                        if s:
                            send_packet(s, 'GRP_INV', inv)
                        else:
                            queue_offline(m, 'GRP_INV', inv)

                elif t == 'GRP_MSG':
                    if not user:
                        continue
                    g = get_group(d.get('groupId', ''))
                    if not g:
                        continue
                    d['sender'] = user
                    for m in g['members']:
                        if m == user:
                            continue
                        with lock:
                            s = online_users.get(m)
                        if s:
                            send_packet(s, 'GRP_MSG', d)
                        else:
                            queue_offline(m, 'GRP_MSG', d)

                elif t == 'GET_GRPS':
                    if not user:
                        continue
                    gs = load_json(GROUPS_FILE)
                    send_packet(conn, 'GRPS_LIST', {'groups': [g for g in gs.values() if user in g['members']]})

                elif t == 'GROUP_LEAVE':
                    if not user:
                        continue
                    gid = d.get('groupId')
                    with lock:
                        gs = load_json(GROUPS_FILE)
                        if gid in gs and user in gs[gid]['members']:
                            gs[gid]['members'].remove(user)
                            if not gs[gid]['members'] or gs[gid]['owner'] == user:
                                del gs[gid]
                            save_json(GROUPS_FILE, gs)
                    for m in gs.get(gid, {}).get('members', []):
                        with lock:
                            s = online_users.get(m)
                        if s:
                            send_packet(s, 'GROUP_MEMBER_REMOVED', {'groupId': gid, 'username': user})

                elif t == 'GRP_READ':
                    if not user:
                        continue
                    gid = d.get('groupId')
                    g = get_group(gid)
                    if g:
                        for m in g['members']:
                            if m == user:
                                continue
                            with lock:
                                s2 = online_users.get(m)
                            if s2:
                                send_packet(s2, 'GRP_READ', {'groupId': gid, 'reader': user, 'timestamp': d.get('timestamp', 0)})

                elif t == 'GRP_DELETE_MSG':
                    if not user:
                        continue
                    g = get_group(d.get('groupId', ''))
                    if g and d.get('sender') == user:
                        for m in g['members']:
                            if m == user:
                                continue
                            with lock:
                                s2 = online_users.get(m)
                            if s2:
                                send_packet(s2, 'GRP_DELETE_MSG', d)

                elif t == 'GRP_REMOVE_MEMBER':
                    if not user:
                        continue
                    gid = d.get('groupId', '')
                    with lock:
                        gs = load_json(GROUPS_FILE)
                        g = gs.get(gid)
                        if g and user == g.get('owner', ''):
                            member = d.get('member', '')
                            if member and member in g['members']:
                                g['members'].remove(member)
                                gs[gid] = g
                                save_json(GROUPS_FILE, gs)
                                for m in g['members'] + [member]:
                                    with lock:
                                        s2 = online_users.get(m)
                                    if s2:
                                        send_packet(s2, 'GRP_REMOVE_MEMBER', {'groupId': gid, 'member': member})

                elif t == 'GRP_ADD_MEMBER':
                    if not user:
                        continue
                    gid = d.get('groupId')
                    nm = d.get('member') or d.get('username')
                    with lock:
                        gs = load_json(GROUPS_FILE)
                        if gid in gs and gs[gid]['owner'] == user and nm and nm not in gs[gid]['members']:
                            gs[gid]['members'].append(nm)
                            save_json(GROUPS_FILE, gs)
                            inv = {'groupId': gid, 'name': gs[gid]['name'], 'owner': gs[gid]['owner'], 'members': gs[gid]['members'], 'inviter': user}
                            with lock:
                                s = online_users.get(nm)
                            if s:
                                send_packet(s, 'GRP_INV', inv)
                            else:
                                queue_offline(nm, 'GRP_INV', inv)
                            for m in gs[gid]['members']:
                                if m == nm:
                                    continue
                                with lock:
                                    s2 = online_users.get(m)
                                if s2:
                                    send_packet(s2, 'GRP_ADD_MEMBER', {'groupId': gid, 'member': nm, 'members': gs[gid]['members']})

                elif t == 'GRP_TYPING':
                    if not user:
                        continue
                    g = get_group(d.get('groupId', ''))
                    if g:
                        for m in g['members']:
                            if m == user:
                                continue
                            with lock:
                                s = online_users.get(m)
                            if s:
                                send_packet(s, 'GRP_TYPING', {'groupId': d.get('groupId'), 'sender': user})

            except Exception as e:
                print(f'[HANDLER ERR] {e}')
                traceback.print_exc()

    except Exception as e:
        print(f'[LOOP ERR] {addr}: {e}')
    finally:
        if user:
            with lock:
                if online_users.get(user) is conn:
                    del online_users[user]
                ls = load_json(PROFILES_FILE)
                if user not in ls:
                    ls[user] = {}
                ls[user]['lastSeen'] = int(time.time() * 1000)
                save_json(PROFILES_FILE, ls)
                print(f'[-] {user}')
        try:
            conn.close()
        except (OSError, socket.error):
            pass


def start_server():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((HOST, PORT))
    s.listen(100)
    print(f'[SERVER] VeilChat listening on {HOST}:{PORT}')
    while True:
        try:
            conn, addr = s.accept()
            conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            threading.Thread(target=handle_client, args=(conn, addr), daemon=True).start()
        except Exception as e:
            print(f'[ACCEPT ERR] {e}')
            time.sleep(0.5)


if __name__ == '__main__':
    start_server()

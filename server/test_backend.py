import unittest
import socket
import threading
import time
import json
import os
import shutil
import tempfile
import sys
import importlib.util

# Load server.py directly by file path
server_dir = os.path.dirname(os.path.abspath(__file__))
server_path = os.path.join(server_dir, 'server.py')
spec = importlib.util.spec_from_file_location("veilchat_server", server_path)
srv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(srv)

media_path = os.path.join(server_dir, 'media_server.py')
mspec = importlib.util.spec_from_file_location("veilchat_media_server", media_path)
media_srv = importlib.util.module_from_spec(mspec)
mspec.loader.exec_module(media_srv)

class BackendUnitTests(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.orig_users = srv.USERS_FILE
        self.orig_offline = srv.OFFLINE_FILE
        self.orig_groups = srv.GROUPS_FILE
        self.orig_profiles = srv.PROFILES_FILE

        srv.USERS_FILE = os.path.join(self.test_dir, 'users.json')
        srv.OFFLINE_FILE = os.path.join(self.test_dir, 'offline.json')
        srv.GROUPS_FILE = os.path.join(self.test_dir, 'groups.json')
        srv.PROFILES_FILE = os.path.join(self.test_dir, 'profiles.json')

    def tearDown(self):
        srv.USERS_FILE = self.orig_users
        srv.OFFLINE_FILE = self.orig_offline
        srv.GROUPS_FILE = self.orig_groups
        srv.PROFILES_FILE = self.orig_profiles
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_save_and_verify_user(self):
        ok, msg = srv.save_user("testuser", "securepass123")
        self.assertTrue(ok, f"User registration failed: {msg}")

        # Verify valid credentials
        self.assertTrue(srv.verify_user("testuser", "securepass123"))
        # Verify invalid credentials
        self.assertFalse(srv.verify_user("testuser", "wrongpass"))
        # Verify non-existent user
        self.assertFalse(srv.verify_user("nouser", "securepass123"))
        # Verify duplicate registration rejection
        dup_ok, dup_msg = srv.save_user("testuser", "otherpass")
        self.assertFalse(dup_ok)
        self.assertIn("already taken", dup_msg)

    def test_offline_queue_and_delivery(self):
        msg_payload = {"to_user": "bob", "content": "hello bob", "sender": "alice"}
        srv.queue_offline("bob", "TEXT", msg_payload)

        offline_data = srv.load_json(srv.OFFLINE_FILE)
        self.assertIn("bob", offline_data)
        self.assertEqual(len(offline_data["bob"]), 1)
        self.assertEqual(offline_data["bob"][0]["sender"], "alice")

    def test_group_creation(self):
        grp = srv.create_group("grp_123", "Test Group", "alice", ["alice", "bob"])
        self.assertEqual(grp["id"], "grp_123")
        self.assertEqual(grp["name"], "Test Group")
        self.assertEqual(grp["owner"], "alice")
        self.assertIn("bob", grp["members"])

        fetched = srv.get_group("grp_123")
        self.assertEqual(fetched["id"], "grp_123")

    def test_media_server_health(self):
        with media_srv.app.test_client() as client:
            res = client.get('/health')
            self.assertEqual(res.status_code, 200)
            data = res.get_json()
            self.assertEqual(data.get('status'), 'ok')

if __name__ == '__main__':
    unittest.main()

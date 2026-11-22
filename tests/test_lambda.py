import importlib.util
import json
import pathlib
import unittest
from types import SimpleNamespace
from unittest.mock import patch


MODULE_PATH = pathlib.Path(__file__).parents[1] / "lambda" / "index.py"
SPEC = importlib.util.spec_from_file_location("lambda_index", MODULE_PATH)
index = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(index)


class HandlerTests(unittest.TestCase):
    def setUp(self):
        self.context = SimpleNamespace(aws_request_id="request-123")
        self.event = {"httpMethod": "POST", "path": "/", "body": '{"message":"hello"}'}

    @patch.object(index, "_write_api_access_log")
    @patch.object(index, "_load_runtime_config", return_value={"max_message_length": 100})
    def test_post_returns_message_timestamp_and_request_id(self, _config, _access_log):
        response = index.handler(self.event, self.context)

        self.assertEqual(response["statusCode"], 200)
        body = json.loads(response["body"])
        self.assertEqual(body["message"], "hello")
        self.assertEqual(body["request_id"], "request-123")
        self.assertTrue(body["timestamp"])

    @patch.object(index, "_write_api_access_log")
    def test_invalid_json_returns_400(self, _access_log):
        self.event["body"] = "{"

        self.assertEqual(index.handler(self.event, self.context)["statusCode"], 400)

    @patch.object(index, "_write_api_access_log")
    def test_missing_message_returns_400(self, _access_log):
        self.event["body"] = "{}"

        self.assertEqual(index.handler(self.event, self.context)["statusCode"], 400)

    @patch.object(index, "_write_api_access_log")
    def test_non_post_method_returns_405(self, _access_log):
        self.event["httpMethod"] = "PUT"

        self.assertEqual(index.handler(self.event, self.context)["statusCode"], 405)

    @patch.object(index, "_write_api_access_log")
    def test_health_check_does_not_load_runtime_config(self, _access_log):
        self.event.update({"httpMethod": "GET", "path": "/health"})

        with patch.object(index, "_load_runtime_config") as load_config:
            self.assertEqual(index.handler(self.event, self.context)["statusCode"], 200)
            load_config.assert_not_called()


if __name__ == "__main__":
    unittest.main()

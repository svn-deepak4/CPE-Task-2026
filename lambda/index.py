import json
import logging
import os
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)


class RuntimeConfigError(Exception):
    pass


def _load_runtime_config():
    try:
        import boto3
        from botocore.exceptions import BotoCoreError, ClientError

        parameter = boto3.client("ssm").get_parameter(
            Name=os.environ["PARAMETER_NAME"],
            WithDecryption=True,
        )
        config = json.loads(parameter["Parameter"]["Value"])
        maximum = config["max_message_length"]
        if not isinstance(maximum, int) or maximum < 1:
            raise ValueError("max_message_length must be a positive integer")
        return {"max_message_length": maximum}
    except (BotoCoreError, ClientError, KeyError, ValueError, json.JSONDecodeError) as error:
        raise RuntimeConfigError("Could not load valid runtime configuration") from error


def _write_api_access_log(event, context, status_code):
    from botocore.exceptions import BotoCoreError, ClientError
    import boto3

    record = {
        "request_id": context.aws_request_id,
        "method": event.get("httpMethod", ""),
        "path": event.get("path", ""),
        "status_code": status_code,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    try:
        boto3.client("logs").put_log_events(
            logGroupName=os.environ["API_ACCESS_LOG_GROUP"],
            logStreamName=os.environ["API_ACCESS_LOG_STREAM"],
            logEvents=[
                {
                    "timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
                    "message": json.dumps(record, separators=(",", ":")),
                }
            ],
        )
    except (BotoCoreError, ClientError, KeyError):
        logger.exception("api_access_log_delivery_failed")


def _response(event, context, status_code, body):
    logger.info(
        json.dumps(
            {
                "request_id": context.aws_request_id,
                "method": event.get("httpMethod", ""),
                "path": event.get("path", ""),
                "status_code": status_code,
            },
            separators=(",", ":"),
        )
    )
    _write_api_access_log(event, context, status_code)
    return {
        "statusCode": status_code,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


def handler(event, context):
    method = event.get("httpMethod", "")
    path = event.get("path", "")

    if method == "GET" and path == "/health":
        return _response(event, context, 200, {"status": "ok"})
    if method != "POST":
        return _response(event, context, 405, {"error": "method not allowed"})

    try:
        payload = json.loads(event.get("body") or "")
    except (json.JSONDecodeError, TypeError):
        return _response(event, context, 400, {"error": "body must be valid JSON"})

    if not isinstance(payload, dict) or not isinstance(payload.get("message"), str):
        return _response(event, context, 400, {"error": "message must be a string"})

    try:
        maximum = _load_runtime_config()["max_message_length"]
    except RuntimeConfigError:
        logger.exception("runtime_configuration_load_failed")
        return _response(event, context, 500, {"error": "internal server error"})

    message = payload["message"]
    if len(message) > maximum:
        return _response(event, context, 400, {"error": "message is too long"})

    return _response(
        event,
        context,
        200,
        {
            "message": message,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "request_id": context.aws_request_id,
        },
    )

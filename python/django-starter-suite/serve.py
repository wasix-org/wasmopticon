import os

os.environ["DJANGO_SETTINGS_MODULE"] = "suite_settings"

from django.core.management import call_command
from django.core.servers.basehttp import ThreadedWSGIServer, WSGIRequestHandler
from mysite.wsgi import application


class SuiteServer(ThreadedWSGIServer):
    request_queue_size = 32


if __name__ == "__main__":
    os.environ["DJANGO_SUPERUSER_PASSWORD"] = "local-fixture-password"
    call_command("migrate", interactive=False)
    call_command(
        "createsuperuser",
        interactive=False,
        username="suite-admin",
        email="suite@example.invalid",
    )
    with SuiteServer(
        (os.environ["HOST"], int(os.environ["PORT"])), WSGIRequestHandler
    ) as server:
        server.set_app(application)
        server.serve_forever()

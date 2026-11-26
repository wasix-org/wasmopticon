import os
from wsgiref.simple_server import make_server

os.environ["DJANGO_SETTINGS_MODULE"] = "suite_settings"

from django.core.management import call_command
from mysite.wsgi import application


if __name__ == "__main__":
    os.environ["DJANGO_SUPERUSER_PASSWORD"] = "local-fixture-password"
    call_command("migrate", interactive=False)
    call_command(
        "createsuperuser",
        interactive=False,
        username="suite-admin",
        email="suite@example.invalid",
    )
    with make_server(os.environ["HOST"], int(os.environ["PORT"]), application) as server:
        server.serve_forever()

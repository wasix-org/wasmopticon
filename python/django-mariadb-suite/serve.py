import os

import pymysql

# Django's MySQL backend imports MySQLdb. Use the guest's pure-Python driver.
pymysql.install_as_MySQLdb()
os.environ["DJANGO_SETTINGS_MODULE"] = "suite_settings"

from django.core.management import call_command
from django.core.servers.basehttp import ThreadedWSGIServer, WSGIRequestHandler
from mysite.wsgi import application


if __name__ == "__main__":
    call_command("migrate", interactive=False)
    with ThreadedWSGIServer(
        (os.environ["HOST"], int(os.environ["PORT"])), WSGIRequestHandler
    ) as server:
        server.set_app(application)
        server.serve_forever()

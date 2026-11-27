from mysite.settings import *

ALLOWED_HOSTS = ["127.0.0.1"]
DEBUG = False
ROOT_URLCONF = "suite_urls"
WHITENOISE_USE_FINDERS = True

if DATABASES["default"]["ENGINE"] != "django.db.backends.mysql":
    raise ValueError("The MariaDB fixture needs DB_HOST, DB_PORT, DB_NAME, and DB_USERNAME.")
DATABASES["default"]["OPTIONS"] = {"connect_timeout": 5}

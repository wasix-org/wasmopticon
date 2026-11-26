from mysite.settings import *

ALLOWED_HOSTS = ["127.0.0.1"]
DEBUG = False
ROOT_URLCONF = "suite_urls"
WHITENOISE_USE_FINDERS = True
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": "/tmp/django-starter-suite.sqlite3",
    },
}

from mysite.settings import *

ALLOWED_HOSTS = ["127.0.0.1"]
DEBUG = False
ROOT_URLCONF = "suite_urls"
WHITENOISE_USE_FINDERS = True
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": "/tmp/django-starter-suite.sqlite3",
        # Admin change forms read before writing. Acquire the writer lock
        # at transaction start so SQLite can wait for competing writers.
        "OPTIONS": {"transaction_mode": "IMMEDIATE", "timeout": 10},
    },
}

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {"stderr": {"class": "logging.StreamHandler"}},
    "loggers": {"django.request": {"handlers": ["stderr"], "level": "ERROR", "propagate": False}},
}

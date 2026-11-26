from django.urls import path
from django.views.generic import RedirectView

from mysite.urls import urlpatterns as starter_urls

urlpatterns = [
    path("", RedirectView.as_view(url="/admin/login/")),
    *starter_urls,
]

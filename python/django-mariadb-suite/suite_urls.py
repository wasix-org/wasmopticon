from django.contrib.auth.models import Group
from django.db import IntegrityError, connection, transaction
from django.http import JsonResponse
from django.urls import path
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_POST

from mysite.urls import urlpatterns as starter_urls


@require_GET
def index(request):
    return JsonResponse({"mariadb": connection.mysql_is_mariadb})


@require_GET
def groups(request):
    names = list(Group.objects.order_by("name").values_list("name", flat=True))
    return JsonResponse({"groups": names})


@csrf_exempt
@require_POST
def create_group(request, rollback=False):
    name = request.POST.get("name", "")
    if not 1 <= len(name) <= Group._meta.get_field("name").max_length:
        return JsonResponse({"error": "Provide a valid group name."}, status=400)

    try:
        with transaction.atomic():
            group = Group.objects.create(name=name)
            if rollback:
                transaction.set_rollback(True)
    except IntegrityError:
        return JsonResponse({"error": "Group name already exists."}, status=409)

    return JsonResponse(
        {"id": group.pk, "name": group.name, "rolled_back": rollback},
        status=200 if rollback else 201,
    )


urlpatterns = [
    path("", index),
    path("groups/", groups),
    path("groups/create/", create_group),
    path("groups/rollback/", create_group, {"rollback": True}),
    *starter_urls,
]

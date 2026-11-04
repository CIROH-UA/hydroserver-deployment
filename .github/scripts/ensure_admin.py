# Creates or promotes a HydroServer admin account. Run as an hs-init ECS task with
# `python manage.py shell -c`, with ADMIN_EMAIL, ADMIN_FIRST_NAME, and ADMIN_LAST_NAME set.
#
# New accounts are created without a usable password. The admin sets one using HydroServer's
# Reset Password page. Existing accounts are promoted to admin and otherwise left unchanged.

import os
from django.contrib.auth import get_user_model

User = get_user_model()
email = os.environ["ADMIN_EMAIL"]
user = User.objects.filter(email__iexact=email).first()

if user is None:
    User.objects.create_superuser(
        email=email,
        password=None,
        first_name=os.environ["ADMIN_FIRST_NAME"],
        last_name=os.environ["ADMIN_LAST_NAME"],
    )
    print(f"Created admin account {email}. Set a password using the Reset Password page.")
else:
    user.is_staff = True
    user.is_superuser = True
    user.is_ownership_allowed = True
    user.save()
    print(f"Promoted existing account {user.email} to admin.")

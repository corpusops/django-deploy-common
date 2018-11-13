# Production
ALLOWED_HOSTS = [
    '{{cops_django_hostname}}',
    {% for url in cops_django_alternate_hostnames %}
    '{{url}}',
    {% endfor %}
]
CORS_ORIGIN_WHITELIST = (
    '{{cops_django_hostname}}',
)

# ADMINS = ()
MEDIA_ACCEL_REDIRECT=False

{% if cops_django_devmode %}
CORS_ORIGIN_ALLOW_ALL=True
DEBUG=True
{% endif %}
# This need to be changed in production
SECRET_KEY="{{ cops_django_secret_key }}"
DEFAULT_FROM_EMAIL='{{ cops_django_default_from_email }}'
# EMAIL_HOST = '{{ cops_django_email_server }}'
# EMAIL_HOST_USER = '{{ cops_django_email_host_user }}'
# EMAIL_HOST_PASSWORD = '{{ cops_django_email_host_password }}'
# EMAIL_PORT = '{{ cops_django_email_host_port }}'
USE_TLS = {{ cops_django_email_use_tls }}
EMAIL_BACKEND='django.core.mail.backends.smtp.EmailBackend'
EMAIL_HOST='mailcatcher'
EMAIL_PORT=25
#SERVER_EMAIL = '{{ cops_django_server_email }}'

{{ cops_django_localpy_extra}}

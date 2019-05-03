from ldap3 import Server, Connection, ALL
from datetime import datetime as livetime
from app.models import User


def login_check(username, password):
    try:
        domain_username = 'xx\\{}'.format(username)
        search_base = 'DC=xx,DC=yy'
        search_filter = "(&(objectClass=user)(sAMAccountName={})(memberOf=CN=cure-admin-group,OU=CURE,OU=Groups,OU=Company,DC=xx,DC=yy))".format(username)

        ldap_server = Server('ldap://xx.yy', get_info=ALL)
        ldap_connection = Connection(ldap_server, user=domain_username, password=password)
        user_valid = ldap_connection.bind()

        if user_valid:
            print("Login successful:", user_valid)
            ldap_connection.search(search_base=search_base, search_filter=search_filter)

            if len(ldap_connection.entries) == 1:
                print(username, "is member of cure-admin-group")
                user = User.query.filter_by(username=username).first()
                print(user)
                if user is None:
                    user = User(username=username, lastseen=livetime.utcnow())
                    user.save()
                    print("Saved new login")

                return username
            else:
                print(username, "is not member of cure-admin-group")
                return None

        else:
            print("Login failed:", username)
            return None

    except Exception as e:
        raise e

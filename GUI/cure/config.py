import os
from dotenv import load_dotenv

basedir = os.path.abspath(os.path.dirname(__file__))
load_dotenv(os.path.join(basedir, '.env'))

class Config(object):
    SECRET_KEY = os.environ.get('SECRET')
	DBUN = os.environ.get('DBUSERNAME')
	DBPW = os.environ.get('DBPASSWORD')
	DBHT = os.environ.get('DBHOST')
	DBNM = os.environ.get('DBNAME')
    SQLALCHEMY_DATABASE_URI = os.environ.get('DATABASE_URL') or "postgresql+psycopg2://{}:{}@{}/{}".format(DBUN, DBPW, DBHT, DBNM)
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    FLASK_APP = os.environ.get('FLASK_APP')
    APP_SETTINGS = os.environ.get('SECRET_KEY')
    DEBUG = os.environ.get('DEBUG')
    FLASK_ENV = os.environ.get('FLASK_ENV')

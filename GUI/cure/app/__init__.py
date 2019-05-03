# app/__init__.py
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager
from flask_migrate import Migrate
from flask import Flask
from app.forms import LoginForm
from config import Config
from flask_moment import Moment


# initialize db & login
db = SQLAlchemy()
login = LoginManager()

app = Flask(__name__)
app.config.from_object(Config)
db.init_app(app)
login.init_app(app)
login.login_view = 'login'
migrate = Migrate(app, db)
moment = Moment(app)


from app import views, api,  models

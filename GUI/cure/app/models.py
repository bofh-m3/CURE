from datetime import datetime as livetime
from app import app, login, db
import jwt
from flask_login import UserMixin


@login.user_loader
def load_user(id):
    user = User.query.filter(User.id == int(id)).first()
    return user


class User(UserMixin, db.Model):
    """This class defines the users table """

    __tablename__ = 'users'

    # Define the columns of the users table, starting with the primary key
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(256), nullable=False, unique=True)
    lastseen = db.Column(db.TIMESTAMP, index=True, default=livetime.utcnow)
    authenticated = db.Column(db.Boolean, default=False)

    def __init__(self, username, lastseen):
        """Initialize the user with an email and a password."""
        self.username = username
        self.lastseen = livetime.utcnow()

    def save(self):
        """Save a user to the database.
        This includes creating a new user and editing one.
        """
        db.session.add(self)
        db.session.commit()

    def generate_token(self, user_id):
        """Generates the access token to be used as the Authorization header"""

        try:
            # set up a payload with an expiration time
            payload = {
                'exp': livetime.utcnow() + livetime(minutes=5),
                'iat': livetime.utcnow(),
                'sub': user_id
            }
            # create the byte string token using the payload and the SECRET key
            jwt_string = jwt.encode(
                payload,
                app.config.get('SECRET'),
                algorithm='HS256'
            )
            return jwt_string

        except Exception as e:
            # return an error in string format if an exception occurs
            return str(e)

    @staticmethod
    def decode_token(token):
        """Decode the access token from the Authorization header."""
        try:
            payload = jwt.decode(token, app.config.get('SECRET'))
            return payload['sub']
        except jwt.ExpiredSignatureError:
            return "Expired token. Please log in to get a new token"
        except jwt.InvalidTokenError:
            return "Invalid token. Please login to get a new token"


class Inventory(db.Model):
    """This class defines the Inventory table """

    __tablename__ = 'inventorytable'

    # Define the columns of the users table, starting with the primary key
    detectorid = db.Column(db.Integer, primary_key=True)
    detectorname = db.Column(db.VARCHAR(50), index=True, unique=True)
    refreshrate = db.Column(db.Integer)
    detectorenvironment = db.Column(db.TEXT)
    heartbeatts = db.Column(db.TIMESTAMP, index=True, default=livetime.utcnow)
    heartbeattimeout = db.Column(db.Integer)
    snoozetime = db.Column(db.Integer)
    area = db.Column(db.VARCHAR(50))
    isactive = db.Column(db.Boolean)
    event = db.relationship('Event', backref='id', lazy='dynamic')

    def __init__(self, detectorid, detectorname, refreshrate, detectorenvironment, heartbeatts, heartbeattimeout, \
                 snoozetime, area, isactive):
        self.detectorid = detectorid
        self.detectorname = detectorname
        self.refreshrate = refreshrate
        self.detectorenvironment = detectorenvironment
        self.heartbeatts = heartbeatts
        self.heartbeattimeout = heartbeattimeout
        self.snoozetime = snoozetime
        self.area = area
        self.isactive = isactive

    def save(self):
        """Save a Detector.
        This applies for both creating a new detector
        and updating an existing onupdate
        """
        db.session.add(self)
        db.session.commit()

    @staticmethod
    def get_id(detectorid):
        """This method gets inventory based of id"""
        return Inventory.query.filter_by(detectorid=detectorid)

    def get_all(self):
        """This method gets all inventory items"""
        return Inventory.query.all()

    def delete(self):
        """Deletes a given detector."""
        db.session.delete(self)
        db.session.commit()

    def __repr__(self):
        """Return a representation of a Inventory instance."""
        return "<Inventory: {}({})>".format(self.detectorname, self.detectorid)


class Event(db.Model):
    """This class defines the Event table """

    __tablename__ = 'eventtable'

    eventid = db.Column(db.Integer, primary_key=True)
    detectorid = db.Column(db.Integer, db.ForeignKey('inventorytable.detectorid', ondelete='RESTRICT'))
    datetime = db.Column(db.DateTime, index=True, default=livetime.utcnow)
    status = db.Column(db.VARCHAR(50))
    eventshort = db.Column(db.VARCHAR(512))
    snoozets = db.Column(db.DateTime, default=livetime.utcnow)
    snoozedby = db.Column(db.VARCHAR(50))
    description = db.relationship('Description', backref="id")

    def __init__(self, eventid, detectorid, datetime, status, snoozets, snoozedby):
        self.eventid = eventid
        self.detectorid = detectorid
        self.datetime = datetime
        self.status = status
        self.snoozets = snoozets
        self.snoozedby = snoozedby

    def save(self):
        """Save an Event.
        This applies for both creating a new Event
        and updating an existing onupdate
        """
        db.session.add(self)
        db.session.commit()

    @staticmethod
    def get_all_id(id):
        """This method gets all events based of id"""
        return Event.query.filter_by(detectorid=int(id)).order_by(Event.eventid.desc())

    def get_history_id(id, days):
        """This method gets history of events based of id & days"""
        return Event.query.filter_by(detectorid=int(id)).filter(Event.datetime >= days).order_by(Event.eventid.desc())

    def get_latest(id):
        """This method gets all events based of id"""
        return Event.query.filter_by(detectorid=int(id)).order_by(Event.eventid.desc()).first()

    def get_by_id(id):
        """This method gets all descriptions based of id"""
        return Event.query.filter_by(eventid=id)

    def delete(self):
        """Deletes a given event."""
        db.session.delete(self)
        db.session.commit()

    def __repr__(self):
        """Return a representation of a Event instance."""
        return "<Event: EventID: {}; DetectorID: {}>".format(self.eventid, self.detectorid)


class Description(db.Model):
    """This class defines the Description table """

    __tablename__ = 'eventdescriptiontable'

    eventdescriptionid = db.Column(db.Integer, primary_key=True)
    eventid = db.Column(db.Integer, db.ForeignKey('eventtable.eventid', ondelete='RESTRICT'))
    contenttype = db.Column(db.VARCHAR(50))
    descriptiondetails = db.Column(db.TEXT)

    def __init__(self, eventdescriptionid, eventid, contenttype, descriptiondetails):
        self.eventdescriptionid = eventdescriptionid
        self.eventid = eventid
        self.contenttype = contenttype
        self.descriptiondetails = descriptiondetails

    def save(self):
        """Save a Description.
        This applies for both creating a new description
        and updating an existing onupdate
        """
        db.session.add(self)
        db.session.commit()

    @staticmethod
    def get_long_id(eventid):
        """This method gets all descriptions based of id"""
        return Description.query.filter_by(eventid=eventid)

    def delete(self):
        """Deletes a given description."""
        db.session.delete(self)
        db.session.commit()

    def __repr__(self):
        """Return a representation of a Event instance."""
        return "<Description: EventID: {}; ContentType: {}>".format(self.eventid, self.contenttype)

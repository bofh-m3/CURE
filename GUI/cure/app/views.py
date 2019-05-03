from flask_login import current_user, login_user, logout_user, login_required
from flask import render_template, redirect, url_for, flash, g, json
from app.models import Inventory, Event, User, Description
from app.forms import LoginForm
from app.auth import login_check
from app import app, login, db
from json2html import *


""" Grabs username of the user logged in """
@app.before_request
def before_request():
    g.user = current_user


""" Login """
@app.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated:
        return redirect(url_for('index'))
    form = LoginForm()
    if form.validate_on_submit():
        username, password = form.username.data, form.password.data
        access = login_check(username, password)
        if access is None:
            flash('Invalid username or password')
            return redirect(url_for('login'))
        user = User.query.filter_by(username=access).first()
        print("1. User is authenticated:", user.is_authenticated)
        print("Current user:", current_user)
        if user is None:
            print("No user found")
            return redirect(url_for('login'))

        login_user(user, remember=form.remember_me.data)
        print("2. User is authenticated:", user.is_authenticated)
        print("Current user:", current_user)

        return redirect(url_for('index'))
    return render_template('login.html', form=form)


""" logout. Cant get to this page unless logged in """
@app.route('/logout')
@login_required
def logout():
    logout_user()
    return redirect(url_for('index'))


""" landing page - all detectors """
@app.route('/')
@app.route('/index')
@login_required
def index():
    detectors = Inventory.query.order_by(Inventory.detectorid).all()
    events = []
    for detector in detectors:
        if detector.isactive:
            event = Event.query.filter_by(detectorid=detector.detectorid).order_by(Event.eventid.desc()).first()
            events.append(event)

    return render_template("index.html", detectors=detectors, events=events)


""" compact mode view """
@app.route('/view/compact')
@login_required
def compact():
    detectors = Inventory.query.order_by(Inventory.detectorid).all()
    events = []
    for detector in detectors:
        if detector.isactive:
            event = Event.query.filter_by(detectorid=detector.detectorid).order_by(Event.eventid.desc()).first()
            events.append(event)

    return render_template("compact.html", detectors=detectors, events=events)


""" when clicking detector """
@app.route('/description/<int:id>')
@login_required
def description(id):
    detector = Inventory.query.filter_by(detectorid=id).first()
    if detector.isactive:
        event = Event.query.filter_by(detectorid=detector.detectorid).order_by(Event.eventid.desc()).first()
    if event is not None:
        description = Description.query.filter_by(eventid=event.eventid).order_by(Description.eventid.desc()).first()
    if description.contenttype == "json":
        info = description.descriptiondetails
        info = json2html.convert(json=info, table_attributes="id=\"info-table\" class=\"sortable rgb\"")

    else:
        info = description.descriptiondetails

    return render_template("description.html", detector=detector, event=event, description=description, info=info)


""" When clicking history """
@app.route('/history/<int:id>')
@login_required
def history(id):
    detector = Inventory.query.filter_by(detectorid=id).first()
    if detector.isactive:
        event = Event.query.filter_by(detectorid=detector.detectorid).order_by(Event.eventid.desc())

    return render_template("history.html", detector=detector, event=event)


""" When clicking area """
@app.route('/<area>')
@login_required
def filter_area(area):
    area = area
    detectors = Inventory.query.filter_by(area=area).all()
    events = []
    for detector in detectors:
        if detector.isactive:
            event = Event.query.filter_by(detectorid=detector.detectorid).order_by(Event.eventid.desc()).first()
            events.append(event)

    return render_template("index.html", detectors=detectors, events=events)

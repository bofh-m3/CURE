from flask import request, make_response, jsonify, abort
from flask_login import current_user
from datetime import datetime as livetime
from datetime import timedelta
from app.models import Inventory, Event, Description, User
from app import app


@app.route('/api/snooze/<int:id>', methods=['GET', 'PATCH'])
def snooze_by_id(id, **kwargs):
    print("Incomming snooze request")
    event = Event.query.filter_by(eventid=id).first()
    if not event:
        print("Event not found")
        # Raise an HTTPException with a 404 not found status code
        abort(404)

    if request.method == 'PATCH':
        event.snoozedby = current_user.username
        event.snoozets = livetime.utcnow()
        event.save()
        response = {
            'eventid': event.eventid,
            'detectorid': event.detectorid,
            'datetime': event.datetime,
            'status': event.status,
            'eventshort': event.eventshort,
            'snoozets': event.snoozets,
            'snoozedby': event.snoozedby
        }
        return make_response(jsonify(response)), 200

    else:
        # GET
        response = jsonify({
            'eventid': event.eventid,
            'detectorid': event.detectorid,
            'datetime': event.datetime,
            'status': event.status,
            'eventshort': event.eventshort,
            'snoozets': event.snoozets,
            'snoozedby': event.snoozedby
        })
        return make_response(response), 200

		
@app.route('/api/unsnooze/<int:id>', methods=['GET', 'PATCH'])
def unsnooze_by_id(id, **kwargs):
    print("Incomming unsnooze request")
    event = Event.query.filter_by(eventid=id).first()
    if not event:
        print("Event not found")
        # Raise an HTTPException with a 404 not found status code
        abort(404)

    if request.method == 'PATCH':
        event.snoozedby = None
        event.snoozets = None
        event.save()
        response = {
            'eventid': event.eventid,
            'detectorid': event.detectorid,
            'datetime': event.datetime,
            'status': event.status,
            'eventshort': event.eventshort,
            'snoozets': event.snoozets,
            'snoozedby': event.snoozedby
        }
        return make_response(jsonify(response)), 200

    else:
        # GET
        response = jsonify({
            'eventid': event.eventid,
            'detectorid': event.detectorid,
            'datetime': event.datetime,
            'status': event.status,
            'eventshort': event.eventshort,
            'snoozets': event.snoozets,
            'snoozedby': event.snoozedby
        })
    return make_response(response), 200
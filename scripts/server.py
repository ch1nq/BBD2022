import json

from typing import List
from flask import Flask, request, redirect
from scripts.contract import TicketingSystemAPI
from brownie.exceptions import VirtualMachineError

# TODO: Refactor these global variables. It is bad design style, but works for
# this prototype.
app = Flask(__name__)
system = TicketingSystemAPI(0)


def start_server():
    app.run()


@app.route("/")
def hello_world():
    return redirect("/id/0")


def error_page(user_id, error_msg):
    with open("static/error.html") as error_template:
        html = (
            error_template.read()
            .replace("{user_id}", str(user_id))
            .replace("{error_msg}", str(error_msg))
        )
    return html


def event_list(user_id, events) -> str:
    events = [
        f'<li><a href="/id/{user_id}/event/{event["event_id"]}">{event["name"]}</a></li>'
        for event in events
    ]
    return f"""
        <ul>
        {''.join(events)}
        </ul>
    """


def ticket_list(user_id, tickets) -> str:
    def foo(ticket):
        event = system.get_event(ticket["event_id"])
        return f"""
            <li><a href="/id/{user_id}/ticket/{ticket["ticket_id"]
            }">ID: {
                ticket["ticket_id"]
            } - {
               event["name"]
            }, seat {
                ticket["seat_id"]
            }</a></li>
        """

    tickets = [foo(ticket) for ticket in tickets]
    return f"""
        <ul>
        {''.join(tickets)}
        </ul>
    """


def ticket_actions(user_id, ticket_id):
    if system.is_ticket_owner(user_id, ticket_id):
        return f"""
            <form action="/id/{user_id}" method="post">
                <input type="hidden" name="ticket_id" value="{ticket_id}">
                Price: <input type="number" name="price" value="100">
                <button name="function" value="set_ticket_for_sale" type="submit">Set for sale</button>
            </form>

            <form action="/id/{user_id}" method="post">
                Reciever: <input type="number" name="reciever">
                <button name="function" value="send_ticket" type="submit">Send</button>
            </form>
        """
    else:
        return f"""
        <form action="/id/{user_id}" method="post">
            <input type="hidden" name="ticket_id" value="{ticket_id}">
            <button name="function" value="buy_ticket" type="submit">Buy ticket</button>
        </form>
        """


@app.route("/id/<user_id>", methods=["POST", "GET"])
def user_page(user_id: int):
    user_id = int(user_id)
    html = ""
    with open("static/index.html") as f:
        html = f.read()

    if request.method == "POST":
        form = request.form
        try:
            match form["function"]:
                case "get_event":
                    system.get_event(form["event_id"])
                case "cancel_event":
                    system.cancel_event(user_id, form["event_id"])
                case "complete_event":
                    system.complete_event(user_id, form["event_id"])
                case "get_ticket":
                    system.get_event(form["ticket_id"])
                case "buy_ticket":
                    system.buy_ticket(user_id, form["ticket_id"])
                case "send_ticket":
                    system.send_ticket(user_id, form["reciever"], form["ticket_id"])
                case "set_ticket_for_sale":
                    system.set_ticket_for_sale(
                        user_id,
                        int(form["ticket_id"]),
                        int(form["price"]),
                    )
                case "withdraw":
                    system.withdraw(user_id)
                case "create_event":
                    system.create_event(
                        user_id,
                        form["event_id"],
                        form["name"],
                        form["description"],
                        int(form["start_timestamp"]),
                        json.loads(form["ticket_contents"]),
                        # [
                        #     {"id": 1, "seat_id": 101, "price": 97},
                        #     {"id": 2, "seat_id": 102, "price": 97},
                        #     {"id": 3, "seat_id": 103, "price": 97},
                        # ],  # TODO,
                    )
                case _ as e:
                    html = error_page(user_id, f"function '{e}' not defined")
        except VirtualMachineError as error:
            html = error_page(user_id, error.revert_msg)
        except ValueError as error:
            html = error_page(user_id, error)

    html = (
        html.replace("{user_id}", str(user_id))
        .replace("{address}", str(system.get_address(user_id)))
        .replace("{balance}", str(system.balance(user_id)))
        .replace("{withdraw_amount}", str(system.availble_to_withdraw(user_id)))
        .replace("{event_overview}", event_list(user_id, system.get_all_events()))
        .replace(
            "{tickets}", ticket_list(user_id, system.get_tickets_for_user(user_id))
        )
    )

    return html


@app.route("/id/<user_id>/create_event/")
def create_event(user_id):
    html = ""
    with open("static/create_event.html") as f:
        html = f.read().replace("{user_id}", str(user_id))
    return html


def is_for_sale_pill(ticket):
    if ticket["is_for_sale"]:
        return "FOR SALE!"
    else:
        return "Not for sale..."


@app.route("/id/<user_id>/ticket/<ticket_id>")
def ticket_page(user_id, ticket_id):
    user_id = int(user_id)
    ticket_id = int(ticket_id)
    ticket = system.get_ticket(ticket_id)
    html = ""
    with open("static/ticket.html") as f:
        html = (
            f.read()
            .replace("{user_id}", str(user_id))
            .replace("{ticket_id}", str(ticket_id))
            .replace("{is_for_sale}", is_for_sale_pill(ticket))
            .replace("{event}", system.get_event(ticket["event_id"])["name"])
            .replace("{seat_id}", str(ticket["seat_id"]))
            .replace("{price}", str(ticket["price"]))
            .replace("{ticket_actions}", ticket_actions(user_id, ticket_id))
        )
    return html


def event_actions(user_id, event_id):
    if system.is_event_owner(user_id, event_id):
        return f"""
            <form action="/id/{user_id}" method="post">
                <input type="hidden" name="event_id" value="{event_id}">
                <button name="function" value="cancel_event" type="submit">Cancel event</button>
            </form>
            <form action="/id/{user_id}" method="post">
                <input type="hidden" name="event_id" value="{event_id}">
                <button name="function" value="complete_event" type="submit">Complete event</button>
            </form>
        """
    else:
        return ""


@app.route("/id/<user_id>/event/<event_id>")
def event_page(user_id, event_id):
    event_id = int(event_id)
    html = ""
    with open("static/event.html") as f:
        html = (
            f.read()
            .replace("{user_id}", str(user_id))
            .replace("{event_id}", str(event_id))
            .replace("{event_status}", system.get_event(event_id)["status"])
            .replace(
                "{tickets_for_sale}",
                ticket_list(user_id, system.get_tickets_for_sale(event_id)),
            )
            .replace("{event_actions}", event_actions(int(user_id), event_id))
        )
    return html

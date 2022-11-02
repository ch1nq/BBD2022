import json

from typing import List
from flask import Flask, request, redirect
from scripts.contract import TicketingSystemAPI
from brownie.exceptions import VirtualMachineError
from brownie import accounts

# TODO: Refactor these global variables. It is bad design style, but works for
# this prototype.
app = Flask(__name__)
system = TicketingSystemAPI(0)


def start_server():
    reduce_money()
    app.run()


def reduce_money():
    hidden_account = accounts[9]
    for user_id in range(9):
        accounts[user_id].transfer(to=hidden_account, amount=999999999999999999000)


def get_component(component_name) -> str:
    html = ""
    with open(f"static/{component_name}.html") as f:
        html = f.read()
    return html


@app.route("/")
def hello_world():
    return redirect("/id/0")


def error_page(user_id, error_msg):
    with open("static/error.html") as error_template:
        html = (
            error_template.read()
            .replace("{header}", get_component("header"))
            .replace("{navbar}", get_component("navbar"))
            .replace("{user_id}", str(user_id))
            .replace("{error_msg}", str(error_msg))
        )
    return html


@app.route("/user-select")
def user_select():
    return get_component("user_select").replace("{header}", get_component("header"))


def event_list(user_id, events) -> str:
    events = [
        f"""<a href="/id/{user_id}/event/{event["event_id"]}" class="btn btn-outline-secondary btn-sm">
                {event["name"]}
            </a>
        """
        for event in events
    ]
    if events:
        return f"""
            <div class="vstack gap-2">
                {''.join(events)}
            </div>
        """
    else:
        return """
            <div class="alert alert-secondary" role="alert">
                No events found.
            </div>
        """


def ticket_list(user_id, tickets) -> str:
    def foo(ticket):
        event = system.get_event(ticket["event_id"])
        return f"""
            <a href="/id/{user_id}/ticket/{ticket["ticket_id"]}" class="btn btn-outline-secondary btn-sm">
                ID: {ticket["ticket_id"]} - {event["name"]}, seat {ticket["seat_id"]}
            </a>
        """

    tickets = [foo(ticket) for ticket in tickets]
    if tickets:
        return f"""
            <div class="vstack gap-2">
                {''.join(tickets)}
            </div>
        """
    else:
        return """
            <div class="alert alert-secondary" role="alert">
                No tickets found.
            </div>
        """


def ticket_actions(user_id, ticket_id):
    ticket = system.get_ticket(ticket_id)
    if system.is_ticket_owner(user_id, ticket_id):
        if ticket["is_for_sale"]:
            market_action = """ 
                <div class="d-md-flex justify-content-md-between">
                    <p>Ticket is currently for sale.</p>
                    <button class="btn btn-primary" name="function" value="remove_from_sale" type="submit">Cancel sale</button>
                </div>
            """
        else:
            market_action = """
                <div class="input-group mb-3">
                    <div class="form-floating">
                        <input class="form-control" id="ticket--sell" type="number" name="price" placeholder="100">
                        <label for="ticket--sell" class="form-label">Price</label>
                    </div>
                    <button class="btn btn-primary" name="function" value="set_ticket_for_sale" type="submit">Set for sale</button>
                </div>
            """

        return f"""
            <form action="/id/{user_id}" method="post">
                <input class="form-control" type="hidden" name="ticket_id" value="{ticket_id}">
                {market_action}
                <hr>
                <div class="input-group mb-3">
                    <div class="form-floating">
                        <input class="form-control" id="ticket--reciever" type="number" name="reciever" placeholder="">
                        <label for="ticket--reciever" class="form-label">Reciever</label>
                    </div>
                    <button class="btn btn-primary" name="function" value="send_ticket" type="submit">Send</button>
                </div>
            </form>
        """
    else:
        return f"""
        <form action="/id/{user_id}" method="post">
            <input type="hidden" name="ticket_id" value="{ticket_id}">
            <button class="btn btn-success" name="function" value="buy_ticket" type="submit">Buy ticket</button>
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
                    system.send_ticket(
                        user_id, int(form["reciever"]), form["ticket_id"]
                    )
                case "set_ticket_for_sale":
                    system.set_ticket_for_sale(
                        user_id,
                        int(form["ticket_id"]),
                        int(form["price"]),
                    )
                case "remove_from_sale":
                    system.remove_from_sale(user_id, int(form["ticket_id"]))
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
        html.replace("{header}", get_component("header"))
        .replace("{navbar}", get_component("navbar"))
        .replace("{user_id}", str(user_id))
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
        html = (
            f.read()
            .replace("{header}", get_component("header"))
            .replace("{navbar}", get_component("navbar"))
            .replace("{user_id}", str(user_id))
        )
    return html


def event_link(event_id):
    event = system.get_event(event_id)
    return f"""<a href="/id/{{user_id}}/event/{event_id}">{event["name"]}</a>"""


@app.route("/id/<user_id>/ticket/<ticket_id>")
def ticket_page(user_id, ticket_id):
    user_id = int(user_id)
    ticket_id = int(ticket_id)
    ticket = system.get_ticket(ticket_id)
    html = ""
    with open("static/ticket.html") as f:
        html = (
            f.read()
            .replace("{header}", get_component("header"))
            .replace("{navbar}", get_component("navbar"))
            .replace("{event}", event_link(ticket["event_id"]))
            .replace("{user_id}", str(user_id))
            .replace("{ticket_id}", badge(f"ID: {ticket_id}"))
            .replace("{is_for_sale}", is_for_sale_pill(ticket))
            .replace("{seat_id}", badge(f"Seat no.: {ticket['seat_id']}", "warning"))
            .replace("{ticket_actions}", ticket_actions(user_id, ticket_id))
        )
    return html


def event_actions(user_id, event_id):
    if system.is_event_owner(user_id, event_id):
        return f"""
            <form action="/id/{user_id}" method="post" class="d-grid gap-2 d-md-flex justify-content-md-end mt-3">
                <input class="form-control" type="hidden" name="event_id" value="{event_id}">
                <button class="btn btn-outline-danger" name="function" value="cancel_event" type="submit">Cancel event</button>
                <button class="btn btn-primary" name="function" value="complete_event" type="submit">Complete event</button>
            </form>
        """
    else:
        return ""


def badge(content, color="secondary"):
    return f"""<span class="badge bg-{color}">{content}</span>"""


def is_owner_badge(user_id, event_id):
    if system.is_event_owner(user_id, event_id):
        return badge("You own this event", "success")
    else:
        return ""


def status_badge(event):
    status = event["status"]
    match status:
        case "Active":
            color = "primary"
        case "Completed":
            color = "secondary"
        case "Cancelled":
            color = "danger"
        case _:
            color = None
    return badge(f"Status: {status}", color)


def is_for_sale_pill(ticket):
    if ticket["is_for_sale"]:
        return badge(f"For sale: {ticket['price']}ω", "success")
    else:
        return badge("Not for sale", "danger")


@app.route("/id/<user_id>/event/<event_id>")
def event_page(user_id, event_id):
    event_id = int(event_id)
    event = system.get_event(event_id)
    html = ""
    with open("static/event.html") as f:
        html = (
            f.read()
            .replace("{header}", get_component("header"))
            .replace("{navbar}", get_component("navbar"))
            .replace("{user_id}", str(user_id))
            .replace("{event_name}", event["name"])
            .replace("{event_id}", badge(f"ID: {event_id}"))
            .replace("{event_status}", status_badge(event))
            .replace("{you_are_owner}", is_owner_badge(user_id, event_id))
            .replace(
                "{tickets_for_sale}",
                ticket_list(user_id, system.get_tickets_for_sale(event_id)),
            )
            .replace("{event_actions}", event_actions(int(user_id), event_id))
        )
    return html

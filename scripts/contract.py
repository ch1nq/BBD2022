from lib2to3.pytree import convert
from tkinter import E
from brownie import accounts, TicketingSystem
from brownie.convert.datatypes import ReturnValue
from typing import Dict, List
import json


class TicketingSystemAPI:
    def __init__(self, account_index):
        self.account = accounts[account_index]
        self.contract = TicketingSystem.deploy({"from": self.account})

    def _parse_event(self, event_tuple: ReturnValue, event_id=None) -> Dict:
        fields = [
            "owner",
            "name",
            "description",
            "start_timestamp",
            "status",
            "ticket_ids",
        ]
        event = {field: value for field, value in zip(fields, event_tuple, strict=True)}
        event["status"] = {
            0: "DoesNotExist",
            1: "Active",
            2: "Cancelled",
            3: "Completed",
        }[int(event["status"])]
        if event_id:
            event["event_id"] = event_id
        return event

    def _parse_ticket(self, ticket_tuple, ticket_id=None) -> Dict:
        fields = [
            "owner",
            "event_id",
            "seat_id",
            "price",
            "is_for_sale",
            "is_payed_for",
        ]
        ticket = {field: value for field, value in zip(fields, ticket_tuple)}
        if ticket_id:
            ticket["ticket_id"] = ticket_id
        return ticket

    def create_event(
        self,
        user_id: int,
        event_id: int,
        name: str,
        description: str,
        start_timestamp: int,
        ticket_contents: List[dict],
    ):
        self.contract.createEvent(
            event_id,
            name,
            description,
            start_timestamp,
            [
                (ticket["id"], ticket["seat_id"], ticket["price"])
                for ticket in ticket_contents
            ],
            {"from": accounts[user_id]},
        )

    def get_address(self, user_id):
        return accounts[user_id].address

    def get_event(self, event_id):
        event = self._parse_event(self.contract.getEvent(event_id))
        if event["status"] == "DoesNotExist":
            return f"Event with id '{event_id}' does not exist."
        else:
            return event

    def is_ticket_owner(self, user_id, ticket_id):
        address = accounts[user_id]
        return address == self.get_ticket(ticket_id)["owner"]

    def get_ticket(self, ticket_id):
        ticket_tuple = self.contract.tickets(ticket_id)
        return self._parse_ticket(ticket_tuple, ticket_id)

    def balance(self, user_id):
        return accounts[user_id].balance()

    def availble_to_withdraw(self, user_id):
        return self.contract.getPendingReturns({"from": accounts[user_id]})

    def set_ticket_for_sale(self, user_id, ticket_id, price):
        self.contract.setTicketForSale(ticket_id, price, {"from": accounts[user_id]})

    def remove_from_sale(self, user_id, ticket_id):
        self.contract.removeTicketFromSale(ticket_id, {"from": accounts[user_id]})

    def send_ticket(self, user_id, reciever_id, ticket_id):
        reciever_address = accounts[reciever_id]
        self.contract.sendTicket(
            ticket_id, reciever_address, {"from": accounts[user_id]}
        )

    def buy_ticket(self, user_id, ticket_id):
        price = self.get_ticket(ticket_id)["price"]
        self.contract.buyTicket(ticket_id, {"from": accounts[user_id], "value": price})

    def cancel_event(self, user_id, event_id):
        self.contract.cancelEvent(event_id, {"from": accounts[user_id]})

    def complete_event(self, user_id, event_id):
        self.contract.completeEvent(event_id, {"from": accounts[user_id]})

    def is_event_owner(self, user_id, event_id):
        return self.get_event(event_id)["owner"] == accounts[user_id]

    def withdraw(self, user_id):
        self.contract.withdraw({"from": accounts[user_id]})

    def get_all_events(self):
        id_and_events = self.contract.getAllEvents()

        return [
            self._parse_event(event_tuple, event_id)
            for event_id, event_tuple in zip(id_and_events[0], id_and_events[1])
        ]

    def get_tickets_for_sale(self, event_id):
        ids = self.get_event(event_id)["ticket_ids"]
        tickets = [self.get_ticket(ticket_id) for ticket_id in ids]
        tickets_for_sale = filter(lambda x: x["is_for_sale"], tickets)
        return tickets_for_sale

    def get_tickets_for_user(self, user_id):
        address = accounts[user_id]
        return [
            self.get_ticket(ticket_id)
            for ticket_id in self.contract.getTicketsForUser(address)
        ]

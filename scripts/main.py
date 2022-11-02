import scripts.server as server


def main():
    server.start_server()

    # system.create_event(
    #     event_id=123,
    #     name="My Event",
    #     description="https://zombo.com",
    #     start_timestamp=1337,
    #     ticket_contents=[
    #         {"id": 1, "seat_id": 101, "price": 97},
    #         {"id": 2, "seat_id": 102, "price": 97},
    #         {"id": 3, "seat_id": 103, "price": 97},
    #     ],
    # )

    # print(system.get_event(123))
    # print(system.get_ticket(1))

    # system.buy_ticket(accounts[1], 1)

    # print(system.get_ticket(1))

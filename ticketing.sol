// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

contract TicketingSystem {

    // Type aliases used to clarify roles 
    type Host is address;
    type User is address;
    type EventID is uint256;
    type TicketID is uint256;
    type SeatID is uint32;

    struct Event {
        Host owner;
        string name;
        string description;
        uint256 start_timestamp;
        EventStatus status;
    }

        
    enum EventStatus {
        DoesNotExist, /// The default value - used to check if an event exists
        Active, 
        Cancelled, 
        Completed 
    }

    struct Ticket {
        User owner;
        EventID event_id;
        SeatID seat_id;
        uint256 price; /// The price the ticket is selling for
        // string encrypted_ticket_id; /// The id of the ticket encrypted using the owners private key
    }

    /// 
    struct TicketContent {
        TicketID id;
        SeatID seat_id;
        uint256 price;
    }

    // Variables
    mapping(EventID => Event) public events;
    mapping(TicketID => Ticket) public tickets;
    mapping(Host => mapping(EventID => bool)) public ownershipEvents;
    mapping(User => mapping(TicketID => bool)) public ownershipTickets;

    // Events:
    // event created
    // event cancelled 

    // Errors:
    // 

    constructor() {}

    /// Creates a new event with the message sender as the host
    function createEvent(
        EventID event_id,
        string memory name,
        string memory description,
        uint256 start_timestamp,
        TicketContent[] memory ticket_contents 
    ) public {        
        require(events[event_id].status == EventStatus.DoesNotExist);

        // Initialize event and associate it with the host
        ownershipEvents[Host.wrap(msg.sender)][event_id] = true;
        events[event_id] = Event({
            owner: Host.wrap(msg.sender),
            name: name,
            description: description,
            start_timestamp: start_timestamp,
            status: EventStatus.Active
        });

        // Create tickets and assign the host as the owner of them
        for (uint i = 0; i < ticket_contents.length; i++) {
            TicketID ticket_id = ticket_contents[i].id;
            ownershipTickets[User.wrap(msg.sender)][ticket_id] = true;
            tickets[ticket_id] = Ticket({
                owner: User.wrap(msg.sender),
                event_id: event_id,
                seat_id: ticket_contents[i].seat_id,
                price: ticket_contents[i].price
            });
        }
    }

    /// 
    function transferTicket(address reciever, TicketID ticket_id) public 
        onlyTicketOwner(ticket_id)
        eventIsActive(tickets[ticket_id].event_id) 
    {
        // You can't transfer tickets to yourself
        require(User.unwrap(tickets[ticket_id].owner) != reciever);

        tickets[ticket_id].owner = User.wrap(reciever);
        ownershipTickets[User.wrap(reciever)][ticket_id] = true;
        ownershipTickets[User.wrap(msg.sender)][ticket_id] = false;

        // TODO: transfer funds from sender to reciever
    }


    /// Marks event as "cancelled", destroys tickets and refunds money to users
    function cancelEvent(EventID event_id) public 
        onlyEventHost(event_id) 
        eventIsActive(event_id) 
    {
        events[event_id].status = EventStatus.Cancelled;
        // TODO: refund users
        // TODO: destroy tickets?
    }

    /// Marks event as "completed" and transfers money to host.
    /// Can only be invoked after the event time is surpassed.
    function completeEvent(EventID event_id) public 
        onlyEventHost(event_id)
        eventIsActive(event_id) 
    {
        events[event_id].status = EventStatus.Completed;
        // TODO: pay host
    }

    /// Ensures that msg.sender is the host of the given event
    modifier onlyEventHost(EventID event_id) {
        require(Host.unwrap(events[event_id].owner) == msg.sender);
        _;
    }

    /// Ensures that msg.sender is the owner of the given ticket
    modifier onlyTicketOwner(TicketID ticket_id) {
        require(User.unwrap(tickets[ticket_id].owner) == msg.sender);
        _;
    }

    /// Ensures that event exists and is active - e.g. not cancelled or complete
    modifier eventIsActive(EventID event_id) {
        require(events[event_id].status == EventStatus.Active);
        _;
    }

    /// Returns the public key of the owner assciated with this ticket
    /// Can be used to verify the ownership of the ticket 
    // function getTicketEncryptedID(
    //     User user, 
    //     TicketID ticket_id
    // ) public view returns (string memory) {
    //     // TODO: verify ticket 
    // }

}

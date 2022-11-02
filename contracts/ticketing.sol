// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

contract TicketingSystem {
    type Host is address;
    type User is address;
    type EventID is uint256;
    type TicketID is uint256;
    type SeatID is uint32;
    type UnixTimestamp is uint256;

    struct Event {
        Host owner;
        string name;
        string description;
        UnixTimestamp start_timestamp; // Unix timestamp
        EventStatus status;
        TicketID[] ticket_ids;
    }

    enum EventStatus {
        DoesNotExist, // The default value - used to check if an event exists
        Active, 
        Cancelled, 
        Completed 
    }

    struct Ticket {
        User owner;
        EventID event_id;
        SeatID seat_id;
        uint256 price; /// The price the ticket is selling for
        bool is_for_sale;
        bool is_payed_for;
        // string encrypted_ticket_id; /// The id of the ticket encrypted using the owners private key
    }

    struct TicketContent {
        TicketID id;
        SeatID seat_id;
        uint256 price;
    }

    /// Address deploying the instance of the contract. It will function as an
    /// intermediary address between users and event hosts. 
    // address systemOwner;
    mapping(address => uint256) pendingReturns;

    mapping(EventID => Event) public all_events;
    mapping(TicketID => Ticket) public tickets;

    mapping(Host => uint256) public ownershipEventsTotal;
    mapping(Host => mapping(uint256 => EventID)) public ownershipEvents;
    
    mapping(User => uint256) public ownershipTicketsTotal;
    mapping(User => mapping(uint256 => TicketID)) public ownershipTickets;
    
    uint256 total_events;
    mapping(uint256 => EventID) public event_ids;

    // Events:
    // event created
    // event cancelled 

    // Ticket errors
    error NotEnoughFunds(uint funds_needed);
    error TicketDoesNotExists(TicketID ticket_id);
    error NotTicketOwner(TicketID ticket_id);
    error TicketNotForSale(TicketID ticket_id);
    error SelfTransfer();
    
    // Event errors
    error EventDoesNotExists(EventID event_id);
    error EventAlreadyExists(EventID event_id);
    error EventNotActive(EventID event_id);
    error NotEventHost(EventID event_id);
    error TimeNotPassedStartDate(uint256 start_time, uint256 current_time);

    constructor() {
        total_events = 0;
    }

    /// Creates a new event with the message sender as the host
    function createEvent(
        EventID event_id,
        string memory name,
        string memory description,
        UnixTimestamp start_timestamp,
        TicketContent[] memory ticket_contents
    ) public {
        require(all_events[event_id].status == EventStatus.DoesNotExist, "Event already exists");

        // Initialize event and associate it with the host
        ownershipEvents[Host.wrap(msg.sender)][ownershipEventsTotal[Host.wrap(msg.sender)]++] = event_id;
        all_events[event_id] = Event({
            owner: Host.wrap(msg.sender),
            name: name,
            description: description,
            start_timestamp: start_timestamp,
            status: EventStatus.Active,
            ticket_ids: new TicketID[](ticket_contents.length)
        });
        event_ids[total_events++] = event_id;

        // Create tickets and assign the host as the owner of them
        for (uint i = 0; i < ticket_contents.length; i++) {
            TicketID ticket_id = ticket_contents[i].id;
            if (User.unwrap(tickets[ticket_id].owner) != address(0x0)){
                revert("A ticket with an ID that already exists was provided");
            }
            ownershipTickets[User.wrap(msg.sender)][ownershipTicketsTotal[User.wrap(msg.sender)]++] = ticket_id;
            tickets[ticket_id] = Ticket({
                owner: User.wrap(msg.sender),
                event_id: event_id,
                seat_id: ticket_contents[i].seat_id,
                price: ticket_contents[i].price,
                is_for_sale: true,
                is_payed_for: false
            });
            all_events[event_id].ticket_ids[i] = ticket_id;
        }
    }

    /// Set ticket for sale at a given price. Once purchased by someone
    function setTicketForSale(TicketID ticket_id, uint256 price) public 
        onlyTicketOwner(ticket_id)
        eventIsActive(tickets[ticket_id].event_id)
    {
        tickets[ticket_id].price = price;
        tickets[ticket_id].is_for_sale = true;
    }

    /// Remove ticket from market. People will not able to purchase it
    function removeTicketFromSale(TicketID ticket_id) public 
        onlyTicketOwner(ticket_id)
        ticketIsForSale(ticket_id)
        eventIsActive(tickets[ticket_id].event_id)
    {
        tickets[ticket_id].is_for_sale = false;
    }

    function transferTicket(TicketID ticket_id, User previous_owner, User new_owner) private 
        eventIsActive(tickets[ticket_id].event_id) 
    {
        // Append ownership of ticket_id to new owner
        ownershipTickets[new_owner][ownershipTicketsTotal[new_owner]++] = ticket_id;

        // Remove ownership of ticket_id from previous owner
        uint256 prev_owner_total_tickets = ownershipTicketsTotal[previous_owner];
        for(uint i = 0; i < prev_owner_total_tickets; i++) {
            uint256 id = TicketID.unwrap(ownershipTickets[previous_owner][i]);
            if(id == TicketID.unwrap(ticket_id)) {
                // Move last element of list here to avoid any gaps in list 
                TicketID last_element = ownershipTickets[previous_owner][prev_owner_total_tickets-1];
                ownershipTickets[previous_owner][i] = last_element;
                ownershipTicketsTotal[previous_owner]--;
                break;
            }
        }
    }

    function sendTicket(TicketID ticket_id, User new_owner) public 
        onlyTicketOwner(ticket_id)
        eventIsActive(tickets[ticket_id].event_id) 
    {
        User previous_owner = User.wrap(msg.sender);
        transferTicket(ticket_id, previous_owner, new_owner);
    }

    /// 
    function buyTicket(TicketID ticket_id) public payable
        ticketIsForSale(ticket_id)
        eventIsActive(tickets[ticket_id].event_id) 
    {
        require(User.unwrap(tickets[ticket_id].owner) != msg.sender, "You cannot transfer tickets to yourself");
        require(msg.value >= tickets[ticket_id].price, "Not enough funds were sent with message");

        User previous_owner = tickets[ticket_id].owner;
        User new_owner = User.wrap(msg.sender);

        tickets[ticket_id].owner = new_owner;
        tickets[ticket_id].is_for_sale = false;
        tickets[ticket_id].is_payed_for = true;

        transferTicket(ticket_id, previous_owner, new_owner);

        // Transfer funds from new owner to previous owner
        pendingReturns[User.unwrap(previous_owner)] += msg.value;
    }

    /// Marks event as "cancelled", destroys tickets and refunds money to users
    function cancelEvent(EventID event_id) public 
        onlyEventHost(event_id) 
        eventIsActive(event_id) 
    {
        all_events[event_id].status = EventStatus.Cancelled;

        // Refund all ticket owners for event 
        for(uint i = 0; i < all_events[event_id].ticket_ids.length; i++) {
            TicketID ticket_id = all_events[event_id].ticket_ids[i];
            
            // Only refund tickets that are payed for - e.g. the tickets
            // issued by the event host that have not been bought by anyone. 
            if (tickets[ticket_id].is_payed_for) {
                address owner_address = User.unwrap(tickets[ticket_id].owner);
                pendingReturns[owner_address] += tickets[ticket_id].price;
            }
        }
        
        // TODO: condsider destroying tickets here, if it makes thing more efficient
    }

    /// Marks event as "completed" and transfers funds to host.
    /// Can only be invoked after the event time is surpassed.
    function completeEvent(EventID event_id) public 
        onlyEventHost(event_id)
        eventIsActive(event_id)
    {
        if(block.timestamp < UnixTimestamp.unwrap(all_events[event_id].start_timestamp)) {
            revert TimeNotPassedStartDate(
                UnixTimestamp.unwrap(all_events[event_id].start_timestamp), 
                block.timestamp
            );
        }
        
        all_events[event_id].status = EventStatus.Completed;
        
        // Pay host
        for(uint i = 0; i < all_events[event_id].ticket_ids.length; i++) {
            TicketID ticket_id = all_events[event_id].ticket_ids[i];
            
            // Only transfer funds for tickets that have been payed for
            // - e.g. not the tickets issued by the event host that have 
            // not been bought by anyone. 
            if (tickets[ticket_id].is_payed_for) {
                pendingReturns[msg.sender] += tickets[ticket_id].price;
            }
        }
    }

    /// Withdraw funds 
    function withdraw() public returns (bool) {
        uint amount = pendingReturns[msg.sender];
        if (amount > 0) {
            // It is important to set this to zero because the recipient
            // can call this function again as part of the receiving call
            // before `send` returns.
            pendingReturns[msg.sender] = 0;

            if (!payable(msg.sender).send(amount)) {
                // No need to call throw here, just reset the amount owing
                pendingReturns[msg.sender] = amount;
                return false;
            }
        }
        return true;
    }

    /// Ensures that msg.sender is the host of the given event
    modifier onlyEventHost(EventID event_id) {
        require(Host.unwrap(all_events[event_id].owner) == msg.sender, "You are not the host of the event");
        _;
    }

    /// Ensures that msg.sender is the owner of the given ticket
    modifier onlyTicketOwner(TicketID ticket_id) {
        require(User.unwrap(tickets[ticket_id].owner) == msg.sender, "You are not the ticket owner");
        _;
    }

    /// Ensures that event exists and is active - e.g. not cancelled or complete
    modifier eventIsActive(EventID event_id) {
        require(all_events[event_id].status == EventStatus.Active, "Event is not active");
        _;
    }

    /// Ensures that a ticket is for sale
    modifier ticketIsForSale(TicketID ticket_id) {
        require(User.unwrap(tickets[ticket_id].owner) != address(0x0), "Ticket does not exist");
        require(tickets[ticket_id].is_for_sale, "Ticket is not for sale");
        _;
    }

    function getPendingReturns() public view returns (uint256) {
        return pendingReturns[msg.sender];
    }

    function getAllEvents() public view returns (EventID[] memory, Event[] memory) {
        Event[] memory _events = new Event[](total_events);
        EventID[] memory _events_ids = new EventID[](total_events);
        for(uint i; i < total_events; i++) {
            _events_ids[i] = event_ids[i];
            _events[i] = all_events[event_ids[i]];
        }
        return (_events_ids, _events);
    }

    function getEvent(EventID event_id) public view returns (Event memory) {
        return all_events[event_id];
    }

    function getTicketsForUser(User user) public view returns (TicketID[] memory) {
        TicketID[] memory _tickets = new TicketID[](ownershipTicketsTotal[user]);
        for(uint i = 0; i < ownershipTicketsTotal[user]; i++) {
            _tickets[i] = ownershipTickets[user][i];
        }
        return _tickets;
    }

}

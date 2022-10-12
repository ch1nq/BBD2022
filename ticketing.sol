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

    mapping(EventID => Event) public events;
    mapping(TicketID => Ticket) public tickets;
    mapping(Host => mapping(EventID => bool)) public ownershipEvents;
    mapping(User => mapping(TicketID => bool)) public ownershipTickets;

    // Events:
    // event created
    // event cancelled 

    // Errors:
    error NotEnoughFunds(uint funds_needed);

    constructor() {
        // systemOwner = payable(msg.sender);
    }

    /// Creates a new event with the message sender as the host
    function createEvent(
        EventID event_id,
        string memory name,
        string memory description,
        UnixTimestamp start_timestamp,
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
            status: EventStatus.Active,
            ticket_ids: new TicketID[](ticket_contents.length)
        });

        // Create tickets and assign the host as the owner of them
        for (uint i = 0; i < ticket_contents.length; i++) {
            TicketID ticket_id = ticket_contents[i].id;
            ownershipTickets[User.wrap(msg.sender)][ticket_id] = true;
            tickets[ticket_id] = Ticket({
                owner: User.wrap(msg.sender),
                event_id: event_id,
                seat_id: ticket_contents[i].seat_id,
                price: ticket_contents[i].price,
                is_for_sale: true,
                is_payed_for: false
            });
            events[event_id].ticket_ids.push(ticket_id);
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

    /// 
    function buyTicket(TicketID ticket_id) public payable
        ticketIsForSale(ticket_id)
        eventIsActive(tickets[ticket_id].event_id) 
    {
        // You can't transfer tickets to yourself
        require(User.unwrap(tickets[ticket_id].owner) != msg.sender);
        require(msg.value >= tickets[ticket_id].price);

        User previous_owner = tickets[ticket_id].owner;
        User new_owner = User.wrap(msg.sender);

        tickets[ticket_id].owner = new_owner;
        tickets[ticket_id].is_for_sale = false;
        tickets[ticket_id].is_payed_for = true;

        ownershipTickets[new_owner][ticket_id] = true;
        ownershipTickets[previous_owner][ticket_id] = false;

        // Transfer funds from new owner to previous owner
        pendingReturns[User.unwrap(previous_owner)] += msg.value;
    }

    /// Marks event as "cancelled", destroys tickets and refunds money to users
    function cancelEvent(EventID event_id) public 
        onlyEventHost(event_id) 
        eventIsActive(event_id) 
    {
        events[event_id].status = EventStatus.Cancelled;

        // Refund all ticket owners for event 
        for(uint i = 0; i < events[event_id].ticket_ids.length; i++) {
            TicketID ticket_id = events[event_id].ticket_ids[i];
            
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
        require(block.timestamp >= UnixTimestamp.unwrap(events[event_id].start_timestamp));
        events[event_id].status = EventStatus.Completed;
        
        // Pay host
        for(uint i = 0; i < events[event_id].ticket_ids.length; i++) {
            TicketID ticket_id = events[event_id].ticket_ids[i];
            
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

    /// Ensures that a ticket is for sale
    modifier ticketIsForSale(TicketID ticket_id) {
        require(tickets[ticket_id].is_for_sale);
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

    function getTicketsForSale(EventID event_id) public view returns (Ticket[] memory) {
        Ticket[] memory event_tickets = new Ticket[](events[event_id].ticket_ids.length);
        uint tickets_for_sale = 0;
        for(uint i; i < events[event_id].ticket_ids.length; i++){
            TicketID ticket_id = events[event_id].ticket_ids[i];
            if(event_tickets[i].is_for_sale) {
                event_tickets[tickets_for_sale] = tickets[ticket_id];
                tickets_for_sale++;
            }
        }
        return event_tickets;
    }

    function getCheapestTickets(EventID event_id) public view returns (Ticket memory) {
        Ticket[] memory tickets_for_sale = getTicketsForSale(event_id);
        uint256 cheapest_ticket_price = getMaxUint();
        uint256 cheapest_ticket_index = getMaxUint();
        for(uint i; i < tickets_for_sale.length; i++) {
            // Stop once the first non-existing ticket is reached, 
            // since we assume that tickets_for_sale contains all tickets
            // for sale in the start of the array.
            if(EventID.unwrap(tickets_for_sale[i].event_id) == 0x0) {
                break;
            }

            // TODO: handle case where multiple tickets are the cheapest
            if(tickets_for_sale[i].price < cheapest_ticket_price) {
                cheapest_ticket_index = i;
            }
        }

        // If the index is larger than the array length then no ticket was found
        require(cheapest_ticket_index > tickets_for_sale.length);

        return tickets_for_sale[cheapest_ticket_index];
    }

    /// Largest uint256 possible. Calculated using underflow 
    function getMaxUint() public pure returns(uint256){
        unchecked{
            return uint256(0) - 1;
        }
    }

}

pragma solidity ^0.4.19;

import "./SafeMath.sol";
import "./PermissionGroups.sol";

/*
    1. The administrator can determine the start proposal time, start voting time, and end time of this voting.
    2. The administrator can determine the lock amount required for the proposal, etc.
    3. Any address can propose a project after the proposal is opened. The proposal needs to lock a certain amount of maro, which will be returned after the voting is completed.
    4. Any address can vote for supported projects after the voting begins.
    5. After the voting ends, the administrator will perform the vote counting operation. For this voting result, the vote counting operation will be carried out according to the balance of the voting address at this time.
    6. After the administrator completes vote counting, users can publicly read the results.
*/

contract Vote is PermissionGroups {
    using SafeMath for uint;

    struct Proposal {
        uint id;                    //  proposal ID
        address proposer;           //  proposer address
        string content;             //  proposal content
        uint deposit;               //  lock maro amount for proposal
        uint voteCount;             //  vote count
        address[] currentVoters;    //  voter address list
        bool disabled;              //  disabled of proposal only by proposer
        mapping(address => uint) recs;          //  records of address and vote
    }


    uint constant public decimals = 18;
    string public name = "";        // name of current event
    uint public proposalID = 1;     // proposal ID start from 1

    uint public proposeStartTime = 0;   // proposal start time
    uint public proposeEndTime = 0;     // proposal end time & vote begin time
    uint public voteEndTime = 0;        // vote end time

    uint public minProposeLockAmount = 10 ** decimals * 100000;
    uint public minVoteBalance = 10 ** decimals * 100;

    mapping (uint => Proposal) public proposals;       //  all proposal
    mapping (address => uint) public voteTarget;       //  address => support proposal
    address[] public voters;                           //  all address list


    // p is proposalID
    // a ia action， 1 create proposal 2 vote 3 refund 4 edit proposal content 5 disable proposal
    // addr is user address
    // amount lock amount for create proposal & balance for vote
    event M(uint indexed p, uint indexed a, address indexed addr,  uint amount);

    // 
    function Vote(string _name) public {
        name = _name;
    }
    
    //
    function setProposeStartTime(uint timestamp) public onlyAdmin {
        proposeStartTime = timestamp;
    }

    //
    function setProposeEndTime(uint timestamp) public onlyAdmin {
        proposeEndTime = timestamp;
    }

    //
    function setVoteEndTime(uint timestamp) public onlyAdmin {
        voteEndTime = timestamp;
    }

    //
    function setMinProposalLockAmount(uint amount) public onlyAdmin {
        minProposeLockAmount = 10 ** decimals * amount;
    }

    function setMinVoteBalance(uint amount) public onlyAdmin {
        minVoteBalance = 10 ** decimals * amount;
    }

    // create proposal
    function propose(string proposal) public payable {
        require(msg.value >= minProposeLockAmount);
        require(block.timestamp >= proposeStartTime && block.timestamp <= proposeEndTime);
        
        Proposal memory p = Proposal({
            id: proposalID,
            proposer: msg.sender,
            content: proposal,
            deposit: msg.value,
            voteCount: 0,
            currentVoters: new address[](0),
            disabled: false
        });

        proposals[proposalID] = p;
        M(proposalID, 1, msg.sender, msg.value);

        proposalID += 1;
    }

    // edit proposal
    function editProposal(uint id, string proposal) public {
        require(block.timestamp >= proposeStartTime && block.timestamp <= proposeEndTime);
        require(msg.sender == proposals[id].proposer);
        proposals[id].content = proposal;
        M(id, 4, msg.sender, 0);

    }

    // disable proposal
    function disableProposal(uint id) public {
        require(block.timestamp >= proposeStartTime && block.timestamp <= proposeEndTime);
        require(msg.sender == proposals[id].proposer);
        proposals[id].disabled = true;
        uint deposit = proposals[id].deposit;
        proposals[id].deposit = 0;
        msg.sender.transfer(deposit);
        M(id, 5, msg.sender, 0);
    }

    // vote for proposal
    function vote(uint id) public {
        require(id>0 && id < proposalID);
        require(msg.sender.balance >= minVoteBalance);
        require(block.timestamp >= proposeEndTime && block.timestamp <= voteEndTime);
        require(proposals[id].disabled == false);

        // check voter address first
        if (voteTarget[msg.sender] > 0) {
            uint pID = voteTarget[msg.sender];
            uint vAmount = proposals[pID].recs[msg.sender];
            proposals[pID].voteCount = proposals[pID].voteCount.sub(vAmount);
            proposals[pID].recs[msg.sender] = 0;
            // ignore record in voters
            // ignore record in currentVoters
        }

        voteTarget[msg.sender] = id;
        proposals[id].recs[msg.sender] = msg.sender.balance;
        proposals[id].voteCount = proposals[id].voteCount.add(msg.sender.balance);
        proposals[id].currentVoters.push(msg.sender);
        voters.push(msg.sender);
        M(proposalID, 2, msg.sender, msg.sender.balance);

    }

    // counting on index of voters
    function counting(uint startIndex, uint len) public onlyAdmin {
        require(block.timestamp > voteEndTime);
        for (uint i = startIndex; i < startIndex + len; i++) {
            address voter = voters[i];
            uint pID = voteTarget[voter];
            uint vAmount = proposals[pID].recs[voter];
            proposals[pID].voteCount = proposals[pID].voteCount.sub(vAmount);
            proposals[pID].voteCount = proposals[pID].voteCount.add(voter.balance);
            proposals[pID].recs[voter] = voter.balance;
        }
    }

    // refund on index of proposals
    function refund(uint startIndex, uint len) public  {
        require(block.timestamp > proposeEndTime);
        for (uint i = startIndex; i < startIndex+len ; i++) {
            if (i < proposalID) {
                address proposer = proposals[i].proposer;
                uint deposit = proposals[i].deposit;
                if (deposit > 0) {
                    proposals[i].deposit = 0;
                    proposer.transfer(deposit);
                    M(i, 3, proposer, deposit);
                }
            }
        }        
    }

    // display all the records
    function displayRecs(uint id, uint startIndex, uint len) public view returns (address[] memory, uint[] memory) {
        address[] memory addrs = new address[](len);
        uint[] memory balance = new uint[](len);
        for (uint i= startIndex; i < startIndex + len; i++ ) {
            if (proposals[id].voteCount > 0) {
                if (proposals[id].currentVoters.length > i) {
                    addrs[i] = proposals[id].currentVoters[i];
                    balance[i] = proposals[id].recs[proposals[id].currentVoters[i]];
                }
            }
        }
        return (addrs, balance);
    }

}
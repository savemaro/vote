pragma solidity ^0.4.19;

import "./SafeMath.sol";
import "./PermissionGroups.sol";

/*
    1. 管理员可以确定这次投票的开始提议时间，开始投票时间，结束时间。
    2. 管理员可以确定提议所需的锁定金额等。
    3. 任何人可以在开放提议后对于项目进行提议，提议需要锁定一定的maro，在投票完成后一律归还。
    4. 任何人可以在投票开始后，对于支持的项目进行投票。
    5. 在投票结束后，由管理员执行计票操作，对于本次的投票结果，按照投票地址此时的balance进行计票操作。
    6. 管理员计票完成后，用户可以公开读取结果。
*/

contract Vote is PermissionGroups {
    using SafeMath for uint;

    struct Proposal {
        uint id;                    //  提议ID
        address proposer;           //  提议地址
        string content;             //  提议内容
        uint deposit;               //  锁定押金
        uint voteCount;             //  临时得票用于显示
        address[] currentVoters;    //  投票人列表
        mapping(address => uint) recs;          //  记录
    }


    uint constant public decimals = 18;
    string public name = "";        // 本次投票合约的名称，可以为空
    uint public proposalID = 1;     // ID 从1开始，用0判断

    uint public proposeStartTime = 0;   // 提案开始时间
    uint public proposeEndTime = 0;     // 提案结束时间
    uint public voteEndTime = 0;        // 投票结束时间

    uint public minProposeLockAmount = 10 ** decimals * 100000;
    uint public minVoteBalance = 10 ** decimals * 100;

    mapping (uint => Proposal) public proposals;       //  所有提议
    mapping (address => uint) public voteTarget;       //  某地址当前的目标提议ID
    address[] public voters;                           //  所有参与投票的人


    // p是总的序号，对应proposalID
    // a是行为， 1 是提出提案， 2 是投票提案 3 退钱
    // addr是对应的用户地址
    // amount是对应的金额，提案的时候是锁定的押金，投票的时候是当前的balance
    event M(uint indexed p, uint indexed a, address indexed addr,  uint amount);

    // 初始化
    function Vote(string _name) public {
        name = _name;
    }
    
    // 设定时间点, 提议开始
    function setProposeStartTime(uint timestamp) public onlyAdmin {
        proposeStartTime = timestamp;
    }

    // 设定时间，提议结束
    function setProposeEndTime(uint timestamp) public onlyAdmin {
        proposeEndTime = timestamp;
    }

    // 设定时间，投票结束
    function setVoteEndTime(uint timestamp) public onlyAdmin {
        voteEndTime = timestamp;
    }

    // 设定提议锁定的价格
    function setMinProposalLockAmount(uint amount) public onlyAdmin {
        minProposeLockAmount = 10 ** decimals * amount;
    }

    function setMinVoteBalance(uint amount) public onlyAdmin {
        minVoteBalance = 10 ** decimals * amount;
    }

    // 提议
    function propose(string proposal) public payable {
        require(msg.value >= minProposeLockAmount);
        require(block.timestamp >= proposeStartTime && block.timestamp <= proposeEndTime);
        
        Proposal memory p = Proposal({
            id: proposalID,
            proposer: msg.sender,
            content: proposal,
            deposit: msg.value,
            voteCount: 0,
            currentVoters: new address[](0)
        });

        proposals[proposalID] = p;
        M(proposalID, 1, msg.sender, msg.value);

        proposalID += 1;
    }

    // 投票
    function vote(uint id) public {
        require(id>0 && id < proposalID);
        require(msg.sender.balance >= minVoteBalance);
        require(block.timestamp >= proposeEndTime && block.timestamp <= voteEndTime);

        // 先检查这个地址是否投过票
        if (voteTarget[msg.sender] > 0) {
            uint pID = voteTarget[msg.sender];
            uint vAmount = proposals[pID].recs[msg.sender];
            proposals[pID].voteCount = proposals[pID].voteCount.sub(vAmount);
            proposals[pID].recs[msg.sender] = 0;
            // 这里可以忽略 voters中的记录
            // 也忽略currentVoters中的记录
        }

        voteTarget[msg.sender] = id;
        proposals[id].recs[msg.sender] = msg.sender.balance;
        proposals[id].voteCount = proposals[id].voteCount.add(msg.sender.balance);
        proposals[id].currentVoters.push(msg.sender);
        voters.push(msg.sender);
        M(proposalID, 2, msg.sender, msg.sender.balance);

    }

    // 计票, index 遍历voters
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

    // 退款， index遍历proposals
    function refund(uint startIndex, uint len) public  {
        require(block.timestamp > proposeEndTime);
        for (uint i = startIndex; i < startIndex+len ; i++) {
            if (i < proposalID) {
                address proposer = proposals[i].proposer;
                uint deposit = proposals[i].deposit;
                proposals[i].deposit = 0;
                proposer.transfer(deposit);
                M(i, 3, proposer, deposit);
            }
        }        
    }

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
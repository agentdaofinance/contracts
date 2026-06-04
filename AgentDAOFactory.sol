// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// Compiler: 0.8.25, Optimization: enabled (runs: 1), viaIR: true

import "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./AgentGovernor.sol";

contract AgentDAOFactory {

    // ─────────────────────────────────────────────
    // Custom Errors
    // ─────────────────────────────────────────────

    error EmptyName();
    error InvalidToken();
    error InvalidQuorum();
    error InvalidVotingPeriod();
    error InvalidDAOType();

    // ─────────────────────────────────────────────
    // Structs
    // ─────────────────────────────────────────────

    struct DAOInfo {
        address governor;
        address timelock;
        address token;
        string  name;
        uint8   daoType;
        address creator;
        uint256 createdAt;
    }

    struct CreateDAOParams {
        string  name;
        address token;
        uint8   daoType;
        uint48  votingDelay;
        uint32  votingPeriod;
        uint256 quorumFraction;
        uint256 timelockDelay;
    }

    // ─────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────

    address public immutable governorImplementation;
    address public immutable timelockImplementation;

    DAOInfo[] private _allDAOs;
    mapping(address => uint256[]) private _daosByCreator;

    // ─────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────

    event DAOCreated(
        address indexed creator,
        address indexed governor,
        address indexed timelock,
        address token,
        string  name,
        uint8   daoType,
        uint256 createdAt
    );

    // ─────────────────────────────────────────────
    // Constructor — implementations provided externally
    // ─────────────────────────────────────────────

    /**
     * @param _governorImpl  Deployed AgentGovernor implementation address
     * @param _timelockImpl  Deployed TimelockControllerUpgradeable implementation address
     */
    constructor(address _governorImpl, address _timelockImpl) {
        require(_governorImpl != address(0), "AgentDAOFactory: invalid governor implementation");
        require(_timelockImpl != address(0), "AgentDAOFactory: invalid timelock implementation");
        governorImplementation = _governorImpl;
        timelockImplementation = _timelockImpl;
    }

    // ─────────────────────────────────────────────
    // Main Function
    // ─────────────────────────────────────────────

    function createDAO(
        string  memory _name,
        address _token,
        uint8   _daoType,
        uint48  _votingDelay,
        uint32  _votingPeriod,
        uint256 _quorumFraction,
        uint256 _timelockDelay
    )
        external
        returns (address governor, address timelock)
    {
        if (bytes(_name).length == 0)                      revert EmptyName();
        if (_token == address(0))                          revert InvalidToken();
        if (_quorumFraction < 1 || _quorumFraction > 100) revert InvalidQuorum();
        if (_votingPeriod == 0)                            revert InvalidVotingPeriod();
        if (_daoType > 1)                                  revert InvalidDAOType();

        CreateDAOParams memory p = CreateDAOParams({
            name:           _name,
            token:          _token,
            daoType:        _daoType,
            votingDelay:    _votingDelay,
            votingPeriod:   _votingPeriod,
            quorumFraction: _quorumFraction,
            timelockDelay:  _timelockDelay
        });

        (governor, timelock) = _deployAndConfigure(p);
    }

    // ─────────────────────────────────────────────
    // Internal
    // ─────────────────────────────────────────────

    function _deployAndConfigure(CreateDAOParams memory p)
        internal
        returns (address governorAddr, address timelockAddr)
    {
        // 1) Clone TimelockController and initialize
        timelockAddr = Clones.clone(timelockImplementation);

        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = address(this);
        executors[0] = address(0);

        TimelockControllerUpgradeable(payable(timelockAddr)).initialize(
            p.timelockDelay,
            proposers,
            executors,
            address(this)
        );

        // 2) Clone AgentGovernor and initialize
        governorAddr = Clones.clone(governorImplementation);

        AgentGovernor(payable(governorAddr)).initialize(
            p.name,
            IVotes(p.token),
            timelockAddr,
            p.votingDelay,
            p.votingPeriod,
            p.quorumFraction
        );

        // 3) Grant roles to governor
        TimelockControllerUpgradeable tl = TimelockControllerUpgradeable(payable(timelockAddr));

        tl.grantRole(tl.PROPOSER_ROLE(),  governorAddr);
        tl.grantRole(tl.CANCELLER_ROLE(), governorAddr);
        tl.grantRole(tl.EXECUTOR_ROLE(),  governorAddr);

        // 4) Revoke temporary factory roles — fully permissionless
        tl.revokeRole(tl.PROPOSER_ROLE(),      address(this));
        tl.revokeRole(tl.DEFAULT_ADMIN_ROLE(), address(this));

        // 5) Store DAOInfo
        uint256 idx = _allDAOs.length;
        _allDAOs.push(DAOInfo({
            governor:  governorAddr,
            timelock:  timelockAddr,
            token:     p.token,
            name:      p.name,
            daoType:   p.daoType,
            creator:   msg.sender,
            createdAt: block.timestamp
        }));
        _daosByCreator[msg.sender].push(idx);

        // 6) Emit event
        emit DAOCreated(
            msg.sender,
            governorAddr,
            timelockAddr,
            p.token,
            p.name,
            p.daoType,
            block.timestamp
        );
    }

    // ─────────────────────────────────────────────
    // Getters
    // ─────────────────────────────────────────────

    function getDAOsByCreator(address _creator)
        external view
        returns (DAOInfo[] memory)
    {
        uint256[] storage indices = _daosByCreator[_creator];
        DAOInfo[] memory result = new DAOInfo[](indices.length);
        for (uint256 i = 0; i < indices.length; i++) {
            result[i] = _allDAOs[indices[i]];
        }
        return result;
    }

    function getAllDAOs() external view returns (DAOInfo[] memory) {
        return _allDAOs;
    }

    function getTotalDAOs() external view returns (uint256) {
        return _allDAOs.length;
    }
}
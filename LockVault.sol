// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";


/**
 * @title cvToken
 * @notice ERC20Votes-compatible custody voting token minted and burned
 *         exclusively by LockVault. Compatible with Governor for on-chain voting.
 */
contract cvToken is ERC20, ERC20Permit, ERC20Votes {
    address public immutable vault;

    constructor(string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
        ERC20Permit(name_)
    {
        vault = msg.sender;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "cvToken: caller is not the vault");
        _;
    }

    function mint(address to, uint256 amount) external onlyVault {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyVault {
        _burn(from, amount);
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}

/**
 * @title LockVault
 * @notice Vault contract where users lock ERC20 tokens and receive
 *         vote-weighted cvTokens in return.
 *
 * Voting Weight Formula:
 *   cvAmount = amount * (1 + lockDuration / MAX_DURATION)
 *   Minimum 1x weight (short lock), maximum 2x weight (MAX_DURATION lock)
 */
contract LockVault {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────

    uint256 public constant MAX_DURATION = 4 * 365 days;
    uint256 public constant MIN_DURATION = 1 days;

    // ─────────────────────────────────────────────
    // Structs
    // ─────────────────────────────────────────────

    struct LockInfo {
        uint256 amount;      // Original token amount locked
        uint256 cvMinted;    // Amount of cvTokens minted
        uint256 unlockTime;  // Unix timestamp when lock expires
        bool    active;      // Whether the lock is currently active
    }

    // ─────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────

    IERC20  public immutable underlyingToken;
    cvToken public immutable votingToken;

    mapping(address => LockInfo) public locks;

    // ─────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────

    event Locked(
        address indexed user,
        uint256 amount,
        uint256 cvMinted,
        uint256 unlockTime
    );

    event Unlocked(
        address indexed user,
        uint256 amount,
        uint256 cvBurned
    );

    event LockIncreased(
        address indexed user,
        uint256 additionalAmount,
        uint256 additionalCv,
        uint256 newTotalAmount,
        uint256 newTotalCv
    );

    event LockExtended(
        address indexed user,
        uint256 additionalDuration,
        uint256 additionalCv,
        uint256 newUnlockTime,
        uint256 newTotalCv
    );

    // ─────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────

    constructor(address _token, string memory _cvName, string memory _cvSymbol) {
        require(_token != address(0), "LockVault: invalid token address");
        underlyingToken = IERC20(_token);
        votingToken = new cvToken(_cvName, _cvSymbol);
    }

    // ─────────────────────────────────────────────
    // Core Functions
    // ─────────────────────────────────────────────

    /**
     * @notice Locks tokens and mints cvTokens proportional to lock duration.
     * @param amount   Amount of underlying tokens to lock (in wei)
     * @param duration Lock duration in seconds
     * @dev Caller must approve this contract before calling lock().
     *      After locking, call cvToken.delegate(userAddress) to activate voting power.
     */
    function lock(uint256 amount, uint256 duration) external {
        require(amount > 0,                "LockVault: amount must be greater than zero");
        require(duration >= MIN_DURATION,  "LockVault: duration below minimum");
        require(duration <= MAX_DURATION,  "LockVault: duration exceeds maximum");
        require(!locks[msg.sender].active, "LockVault: active lock exists, unlock first");

        uint256 cvAmount   = _calculateCvAmount(amount, duration);
        uint256 unlockTime = block.timestamp + duration;

        locks[msg.sender] = LockInfo({
            amount:     amount,
            cvMinted:   cvAmount,
            unlockTime: unlockTime,
            active:     true
        });

        underlyingToken.safeTransferFrom(msg.sender, address(this), amount);
        votingToken.mint(msg.sender, cvAmount);

        emit Locked(msg.sender, amount, cvAmount, unlockTime);
    }

    /**
     * @notice Returns locked tokens once the lock period has expired
     *         and burns the corresponding cvTokens.
     */
    function unlock() external {
        LockInfo storage info = locks[msg.sender];
        require(info.active,                        "LockVault: no active lock found");
        require(block.timestamp >= info.unlockTime, "LockVault: lock period has not expired");

        uint256 amount   = info.amount;
        uint256 cvBurned = info.cvMinted;

        delete locks[msg.sender];

        votingToken.burn(msg.sender, cvBurned);
        underlyingToken.safeTransfer(msg.sender, amount);

        emit Unlocked(msg.sender, amount, cvBurned);
    }

    /**
     * @notice Increases the amount of an existing active lock.
     *         Mints additional cvTokens based on the remaining lock duration.
     * @param additionalAmount Amount of additional tokens to lock (in wei)
     */
    function increaseLockAmount(uint256 additionalAmount) external {
        LockInfo storage info = locks[msg.sender];
        require(info.active,                       "LockVault: no active lock found");
        require(block.timestamp < info.unlockTime, "LockVault: lock already expired, unlock first");
        require(additionalAmount > 0,              "LockVault: amount must be greater than zero");

        uint256 remainingDuration = info.unlockTime - block.timestamp;
        uint256 additionalCv      = _calculateCvAmount(additionalAmount, remainingDuration);

        info.amount   += additionalAmount;
        info.cvMinted += additionalCv;

        underlyingToken.safeTransferFrom(msg.sender, address(this), additionalAmount);
        votingToken.mint(msg.sender, additionalCv);

        emit LockIncreased(msg.sender, additionalAmount, additionalCv, info.amount, info.cvMinted);
    }

    /**
     * @notice Extends the duration of an existing active lock.
     *         Mints additional cvTokens for the extra duration on the full locked amount.
     * @param additionalDuration Extra seconds to add to the current lock expiry
     */
    function extendLockDuration(uint256 additionalDuration) external {
        LockInfo storage info = locks[msg.sender];
        require(info.active,                       "LockVault: no active lock found");
        require(block.timestamp < info.unlockTime, "LockVault: lock already expired, unlock first");
        require(additionalDuration >= MIN_DURATION, "LockVault: extension below minimum");

        uint256 newUnlockTime    = info.unlockTime + additionalDuration;
        uint256 newTotalDuration = newUnlockTime - block.timestamp;
        require(newTotalDuration <= MAX_DURATION,   "LockVault: total duration exceeds maximum");

        uint256 additionalCv = (info.amount * additionalDuration) / MAX_DURATION;

        info.unlockTime = newUnlockTime;
        info.cvMinted  += additionalCv;

        votingToken.mint(msg.sender, additionalCv);

        emit LockExtended(msg.sender, additionalDuration, additionalCv, newUnlockTime, info.cvMinted);
    }

    // ─────────────────────────────────────────────
    // View Functions
    // ─────────────────────────────────────────────

    /**
     * @notice Returns the lock information for a given user.
     */
    function getLockInfo(address user) external view returns (LockInfo memory) {
        return locks[user];
    }

    /**
     * @notice Previews the cvToken amount for a given lock amount and duration.
     */
    function previewCvAmount(uint256 amount, uint256 duration) external pure returns (uint256) {
        return _calculateCvAmount(amount, duration);
    }

    /**
     * @notice Returns the remaining seconds until a user's lock expires.
     *         Returns 0 if no active lock or lock has already expired.
     */
    function timeUntilUnlock(address user) external view returns (uint256) {
        LockInfo storage info = locks[user];
        if (!info.active || block.timestamp >= info.unlockTime) return 0;
        return info.unlockTime - block.timestamp;
    }

    // ─────────────────────────────────────────────
    // Internal
    // ─────────────────────────────────────────────

    /**
     * @dev cvAmount = amount * (MAX_DURATION + duration) / MAX_DURATION
     *      Range: 1x (minimum duration) to 2x (MAX_DURATION).
     */
    function _calculateCvAmount(uint256 amount, uint256 duration)
        internal pure
        returns (uint256)
    {
        return (amount * (MAX_DURATION + duration)) / MAX_DURATION;
    }
}

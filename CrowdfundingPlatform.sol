// SPDX-License-Identifier: MIT
// Crypto Coders
// https://www.youtube.com/@Crypto_Coders
// https://cryptocoder.team
pragma solidity ^0.8.24;

contract CrowdfundingPlatform {
    // --------------------------------------------------
    // Constants
    // --------------------------------------------------
    uint256 public constant PLATFORM_FEE_BPS = 200; // 2%

    // --------------------------------------------------
    // Types
    // --------------------------------------------------

    enum CampaignStatus {
        Pending,
        Active,
        Rejected,
        Successful,
        Failed,
        Cancelled,
        Settled
    }

    struct Campaign {
        address creator;
        string title;
        string metadataURI;
        uint256 goal;
        uint256 durationDays;
        uint256 deadline;
        uint256 totalRaised;
        uint256 feePaid;
        CampaignStatus status;
        bool exists;
    }

    // --------------------------------------------------
    // State
    // --------------------------------------------------

    address public owner;
    uint256 public campaignCount;

    mapping(uint256 => Campaign) public campaigns;

    // campaignId => contributor => amount contributed
    mapping(uint256 => mapping(address => uint256)) public contributions;

    // --------------------------------------------------
    // Events
    // --------------------------------------------------

    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed creator,
        string title,
        uint256 goal
    );

    event CampaignReviewed(uint256 indexed campaignId, bool approved);

    event ContributionReceived(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount
    );

    event CampaignFinalized(
        uint256 indexed campaignId,
        CampaignStatus status,
        uint256 totalRaised
    );

    event FundsClaimed(
        uint256 indexed campaignId,
        address indexed creator,
        uint256 grossAmount,
        uint256 fee,
        uint256 netAmount
    );

    event RefundIssued(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount
    );

    event CampaignCancelled(uint256 indexed campaignId);

    // --------------------------------------------------
    // Errors
    // --------------------------------------------------

    error NotOwner();
    error InvalidTitle();
    error InvalidMetadata();
    error InvalidGoal();
    error InvalidMinimum();
    error InvalidDuration();
    error CampaignNotFound();
    error InvalidStatus();
    error CampaignEnded();
    error CampaignNotEnded();
    error NotCampaignCreator();
    error NothingToRefund();
    error TransferFailed();
    error ReentrantCall();

    // --------------------------------------------------
    // Modifiers
    // --------------------------------------------------

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier campaignExists(uint256 campaignId) {
        if (!campaigns[campaignId].exists) {
            revert CampaignNotFound();
        }
        _;
    }
    uint256 private lockState = 1;

    modifier nonReentrant() {
        if (lockState != 1) revert ReentrantCall();

        lockState = 2;
        _;
        lockState = 1;
    }

    // --------------------------------------------------
    // Constructor
    // --------------------------------------------------

    constructor() {
        owner = msg.sender;
    }

    // --------------------------------------------------
    // Create campaign
    // --------------------------------------------------

    function createCampaign(
        string calldata title,
        string calldata metadataURI,
        uint256 goal,
        uint256 durationDays
    ) external returns (uint256 campaignId) {
        if (bytes(title).length == 0) {
            revert InvalidTitle();
        }

        if (bytes(metadataURI).length == 0) {
            revert InvalidMetadata();
        }

        if (goal == 0) revert InvalidGoal();

        if (durationDays == 0 || durationDays > 30) {
            revert InvalidDuration();
        }

        campaignId = ++campaignCount;

        campaigns[campaignId] = Campaign({
            creator: msg.sender,
            title: title,
            metadataURI: metadataURI,
            goal: goal,
            durationDays: durationDays,
            deadline: 0,
            totalRaised: 0,
            feePaid: 0,
            status: CampaignStatus.Pending,
            exists: true
        });

        emit CampaignCreated(campaignId, msg.sender, title, goal);
    }

    // --------------------------------------------------
    // Single admin function: approve OR reject
    // --------------------------------------------------

    function reviewCampaign(
        uint256 campaignId,
        bool approved
    ) external onlyOwner campaignExists(campaignId) {
        Campaign storage campaign = campaigns[campaignId];

        if (campaign.status != CampaignStatus.Pending) {
            revert InvalidStatus();
        }

        if (approved) {
            campaign.deadline =
                block.timestamp +
                (campaign.durationDays * 1 days);

            campaign.status = CampaignStatus.Active;
        } else {
            campaign.status = CampaignStatus.Rejected;
        }

        emit CampaignReviewed(campaignId, approved);
    }

    // --------------------------------------------------
    // Donate ETH
    // --------------------------------------------------

    function contribute(
        uint256 campaignId
    ) external payable campaignExists(campaignId) {
        Campaign storage campaign = campaigns[campaignId];

        if (campaign.status != CampaignStatus.Active) {
            revert InvalidStatus();
        }

        if (block.timestamp >= campaign.deadline) {
            revert CampaignEnded();
        }

        if (msg.value == 0) {
            revert InvalidMinimum();
        }

        campaign.totalRaised += msg.value;
        contributions[campaignId][msg.sender] += msg.value;

        emit ContributionReceived(campaignId, msg.sender, msg.value);
    }

    // --------------------------------------------------
    // Finalize campaign after deadline
    // Anyone can call
    // --------------------------------------------------

    function finalizeCampaign(
        uint256 campaignId
    ) external campaignExists(campaignId) {
        Campaign storage campaign = campaigns[campaignId];

        if (campaign.status != CampaignStatus.Active) {
            revert InvalidStatus();
        }

        if (block.timestamp < campaign.deadline) {
            revert CampaignNotEnded();
        }

        if (campaign.totalRaised >= campaign.goal) {
            campaign.status = CampaignStatus.Successful;
        } else {
            campaign.status = CampaignStatus.Failed;
        }

        emit CampaignFinalized(
            campaignId,
            campaign.status,
            campaign.totalRaised
        );
    }

    // --------------------------------------------------
    // Claim funds: creator receives 98%, owner receives 2%
    // --------------------------------------------------

    function claimFunds(
        uint256 campaignId
    ) external nonReentrant campaignExists(campaignId) {
        Campaign storage campaign = campaigns[campaignId];

        if (msg.sender != campaign.creator) {
            revert NotCampaignCreator();
        }

        if (campaign.status != CampaignStatus.Successful) {
            revert InvalidStatus();
        }

        uint256 grossAmount = campaign.totalRaised;

        uint256 fee = (grossAmount * PLATFORM_FEE_BPS) / 10000;

        uint256 netAmount = grossAmount - fee;

        // Update state before external ETH transfers.
        campaign.status = CampaignStatus.Settled;
        campaign.feePaid = fee;

        (bool creatorPaid, ) = payable(campaign.creator).call{value: netAmount}(
            ""
        );

        if (!creatorPaid) revert TransferFailed();

        // The platform fee is sent to the current owner.
        if (fee > 0) {
            (bool feePaid, ) = payable(owner).call{value: fee}("");

            if (!feePaid) revert TransferFailed();
        }

        emit FundsClaimed(
            campaignId,
            campaign.creator,
            grossAmount,
            fee,
            netAmount
        );
    }

    // --------------------------------------------------
    // Refund donations from failed campaigns
    // --------------------------------------------------

    function refund(
        uint256 campaignId
    ) external nonReentrant campaignExists(campaignId) {
        Campaign storage campaign = campaigns[campaignId];

        if (campaign.status != CampaignStatus.Failed) {
            revert InvalidStatus();
        }

        uint256 amount = contributions[campaignId][msg.sender];

        if (amount == 0) revert NothingToRefund();

        // Prevent claiming the same refund twice.
        contributions[campaignId][msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");

        if (!success) revert TransferFailed();

        emit RefundIssued(campaignId, msg.sender, amount);
    }

    // --------------------------------------------------
    // Cancel without any donations
    // --------------------------------------------------

    function cancelCampaign(
        uint256 campaignId
    ) external campaignExists(campaignId) {
        Campaign storage campaign = campaigns[campaignId];

        if (msg.sender != campaign.creator) {
            revert NotCampaignCreator();
        }

        if (
            campaign.status != CampaignStatus.Pending &&
            campaign.status != CampaignStatus.Active
        ) {
            revert InvalidStatus();
        }

        if (campaign.totalRaised != 0) {
            revert InvalidStatus();
        }

        campaign.status = CampaignStatus.Cancelled;

        emit CampaignCancelled(campaignId);
    }

    // --------------------------------------------------
    // Read functions
    // --------------------------------------------------

    function getCampaign(
        uint256 campaignId
    ) external view campaignExists(campaignId) returns (Campaign memory) {
        return campaigns[campaignId];
    }

    function getContribution(
        uint256 campaignId,
        address contributor
    ) external view campaignExists(campaignId) returns (uint256) {
        return contributions[campaignId][contributor];
    }
    receive() external payable {}
}

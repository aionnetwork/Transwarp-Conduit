/**
 * This code is licensed under the MIT License
 *
 * Copyright (c) 2019 Aion Foundation https://aion.network/
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
pragma solidity ^0.4.15;

contract Owned {
    address public owner;
    address public ownerCandidate;

    event ChangedOwner(address indexed _newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function Owned() internal {
        owner = msg.sender;
    }

    function changeOwner(address _newOwner) onlyOwner external {
        ownerCandidate = _newOwner;
    }

    function acceptOwnership() external {
        if (msg.sender == ownerCandidate) {
            owner = ownerCandidate;
            ownerCandidate = 0x0;
            ChangedOwner(owner);
        }
    }
}

contract Pausable is Owned {
    bool private paused = false;

    event Paused();
    event Unpaused();

    function isPaused() public constant returns (bool) {
        return paused;
    }

    modifier whenNotPaused() {
        require(!paused);
        _;
    }

    modifier whenPaused() {
        require(paused);
        _;
    }

    function pause() external onlyOwner whenNotPaused {
        paused = true;
        Paused();
    }

    function unpause() external onlyOwner whenPaused {
        paused = false;
        Unpaused();
    }
}

interface IBridgeSignatory {
    function isSignatory(address _signatoryAddress) public constant returns (bool);
    function signatoryCount() public constant returns (uint);
}

library EthBridgeHelpers {

    function addressArrayContains(address[] _array, address _value) internal constant returns (bool) {
        for (uint i = 0; i < _array.length; i++) {
            if (_array[i] == _value) {
                return true;
            }
        }
        return false;
    }

    /// @param _transferHash Hash of the transfer data to be validated
    /// @param _v Output of ECDSA signature
    /// @param _r Output of ECDSA signature
    /// @param _s Output of ECDSA signature
    /// @param _signatoryContract Address of the contract containing valid signatories
    /// @param _quorumSize minimum number of valid signatures required
    /// @return true if _transferHash has been signed by the required number of signatories, false otherwise
    function hasEnoughValidSignatures(
        bytes32 _transferHash,
        uint8[] _v,
        bytes32[] _r,
        bytes32[] _s,
        IBridgeSignatory _signatoryContract,
        uint _quorumSize
    )
        internal
        constant
        returns (bool)
    {
        address[] memory recoveredSigners = new address[](_quorumSize);

        for (uint i = 0; i < _v.length; i++) {
            address recoveredAddress = ecrecover(_transferHash, _v[i], _r[i], _s[i]);
            if (_signatoryContract.isSignatory(recoveredAddress) && !addressArrayContains(recoveredSigners, recoveredAddress)) {
                _quorumSize --;
                recoveredSigners[_quorumSize] = recoveredAddress;
                if (_quorumSize == 0)
                    return true;
            }
        }
        return false;
    }
}

contract EthBridgeAdapter is Pausable {

    //AION
    bytes1 constant sourceNetworkId = 0x1;

    IBridgeSignatory public signatoryContract;

    uint128 public maximumBridgeTransactionGas;
    uint128 public transactionFee;
    uint128 requestId;

    uint128 expectedSourceTransferId;
    address public relayer;
    uint public signatoryQuorumSize; //uint256
    bytes32 public sourceAdapterAddress;
    bool public acceptOnlyAuthorizedSenders;

    mapping(address => bool) public authorizedSenders;
    //mapping of transactionHash => blockNumber
    mapping(bytes32 => uint) public processedTransactions;

    //source events
    event BridgeTransferRequested(uint128 indexed _requestId, address indexed _transactionInitiator, bytes32 indexed _recipientContract, uint128 _gas, bytes _data);
    event AuthorizedSenderAdded(address indexed _newAuthorizedSender);
    event TransactionFeeUpdated(uint128 indexed _txFee);

    //destination events
    event Processed(uint128 indexed _sourceTransferId, bytes32 indexed _sourceTransactionHash, address indexed _recipientContract, bytes32 hash, bool result);
    event AlreadyProcessed(uint indexed _blockNumber);
    event RelayerChanged (address indexed _newRelayer);
    event SignatoryQuorumSizeChanged(uint indexed _newSignatoryQuorumSize); //uint256
    event SignatoryContractAddressChanged(address indexed _newSignatoryContrat);


    modifier onlyRelayer() {
        require(msg.sender == relayer);
        _;
    }

    modifier onlyAssociatedSourceAdaptor(bytes32 _sourceAdapterAddress) {
        require(sourceAdapterAddress == _sourceAdapterAddress);
        _;
    }

    function EthBridgeAdapter(
        address _signatoryContractAddress,
        address _relayer,
        uint _signatoryQuorumSize, //uint256
        uint128 _maximumBridgeTransactionGas,
        uint128 _transactionFee,
        bool _acceptOnlyAuthorizedSenders)
    {
        signatoryContract = IBridgeSignatory(_signatoryContractAddress);
        relayer = _relayer;
        signatoryQuorumSize = _signatoryQuorumSize;
        maximumBridgeTransactionGas = _maximumBridgeTransactionGas;
        transactionFee = _transactionFee;
        acceptOnlyAuthorizedSenders = _acceptOnlyAuthorizedSenders;
    }

    function() public payable {
        revert();
    }

    // ------------- destination -------------

    /// @notice Processes a message transfer request originated on the Aion chain
    /// @dev Each source transaction is processed once and identified using the transaction hash
    /// Additionally, transactions are nonced to keep the order on both chains
    /// @param _sourceTransactionHash Transaction hash from the Aion adapter which contains the BridgeTransferRequested event
    /// @param _recipientContract Contract to call from this adapter
    /// @param _data Encoded function call and arguments
    /// @param _gas Amount of gas to be used by the function call
    /// @param _sourceTransferId Nonce of the Aion transfer request event
    /// @param _v Output of ECDSA signature
    /// @param _r Output of ECDSA signature
    /// @param _s Output of ECDSA signature
    function processTransfer(
        bytes32 _sourceTransactionHash,
        address _recipientContract,
        bytes _data,
        uint128 _gas,
        uint128 _sourceTransferId,
        uint8[] _v,
        bytes32[] _r,
        bytes32[] _s
    )
        public
        onlyRelayer
    {
        if (processedTransactions[_sourceTransactionHash] > 0) {
            AlreadyProcessed(processedTransactions[_sourceTransactionHash]);
            return;
        }
        // if the transaction hash has not been processed yet, it should be the next expected index
        require(_sourceTransferId == expectedSourceTransferId);
        require(_v.length >= signatoryQuorumSize);

        bytes32 hash = computeTransferHash(_sourceTransactionHash, _recipientContract, _data, _gas, _sourceTransferId);

        require(EthBridgeHelpers.hasEnoughValidSignatures(hash, _v, _r, _s, signatoryContract, signatoryQuorumSize));

        bool result;
        if (_gas > 0) {
            result = _recipientContract.call.gas(_gas)(_data);
        } else {
            result = _recipientContract.call(_data);
        }
        processedTransactions[_sourceTransactionHash] = block.number;
        expectedSourceTransferId ++;
        Processed(_sourceTransferId, _sourceTransactionHash, _recipientContract, hash, result);
    }

    /// @notice Updates the associated Aion adapter contract address
    function setSourceAdapterAddress(bytes32 _newAdapterAddress) public onlyOwner {
        sourceAdapterAddress = _newAdapterAddress;
    }

    //uint256
    /// @notice Updates the minimum number of signatures required
    function updateSignatoryQuorumSize(uint _newQuorumSize) public onlyOwner {
        //remove?
        require(_newQuorumSize <= signatoryContract.signatoryCount());
        signatoryQuorumSize = _newQuorumSize;
        SignatoryQuorumSizeChanged(signatoryQuorumSize);
    }

    /// @notice Updates the relayer account
    function updateRelayer(address _newRelayer) public onlyOwner {
        relayer = _newRelayer;
        RelayerChanged(relayer);
    }

    /// @notice Computes blake2b hash
    /// @param _sourceTransactionHash Transaction hash from the Aion adapter which contains the BridgeTransferRequested event
    /// @param _recipientContract Contract to call from this adapter
    /// @param _data Encoded function call and arguments
    /// @param _gas Amount of gas to be used by the function call
    /// @param _sourceTransferId Nonce of the Aion transfer request event
    function computeTransferHash(
        bytes32 _sourceTransactionHash,
        address _recipientContract,
        bytes _data,
        uint128 _gas,
        uint128 _sourceTransferId
    )
        public
        constant
        returns (bytes32)
    {
        return keccak256(_sourceTransactionHash, sourceAdapterAddress, _recipientContract, _data, _gas, _sourceTransferId, sourceNetworkId);
    }
    // ----------------------------------

    // ------------- source -------------

    /// @notice Generates a cross chain transfer request event to be picked up by the bridge
    /// @dev Contract owner can define a fee for each transaction relayed to Aion
    /// @param _destinationContract Recipient contract address to be called on Aion
    /// @param _data Encoded function call and arguments
    /// @param _gas Amount of gas to be used by the function call
    function requestTransfer(
        bytes32 _destinationContract,
        bytes _data,
        uint128 _gas
    )
        external
        whenNotPaused
        payable
    {
        //ensure adapter can return the extra value
        require(msg.value == transactionFee || msg.value - transactionFee < this.balance);

        require(isAuthorizedSender(msg.sender));
        require(0 <= _gas && _gas <= maximumBridgeTransactionGas);
        BridgeTransferRequested(requestId, msg.sender, _destinationContract, _gas, _data);
        requestId ++;
        //transfer the extra value back to the sender
        //Sender contract should be able to deal with the transferred balance
        if(msg.value > transactionFee){
            msg.sender.transfer(msg.value - transactionFee);
        }
    }

    /// @notice Adds the address to the list of accounts authorized to request message transfers
    function addAuthorizedSender(address _newSender) public onlyOwner {
        // mode is not checked. It's not necessary to add senders only if we're validating them
        authorizedSenders[_newSender] = true;
        AuthorizedSenderAdded(_newSender);
    }

    /// @notice Set the policy to either accept requests from a pre-authorized list of senders or any address
    function setAuthorizedSenderPolicy(bool _acceptOnlyAuthorizedSenders) public onlyOwner {
        acceptOnlyAuthorizedSenders = _acceptOnlyAuthorizedSenders;
    }

    /// @notice Updates the maximum amount of gas that can be used on Aion to call a function
    function updateMaximumBridgeTransactionGas(uint128 _maximumBridgeTransactionGas) public onlyOwner {
        maximumBridgeTransactionGas = _maximumBridgeTransactionGas;
    }

    /// @notice Updates the fee for relaying each message to Aion
    function updateTransactionFee(uint128 _transactionFee) public onlyOwner {
        transactionFee = _transactionFee;
        TransactionFeeUpdated(transactionFee);
    }

    /// @return true if the address is authorized to request message transfers, false otherwise
    function isAuthorizedSender(address _senderAddress) public constant returns (bool){
        if (!acceptOnlyAuthorizedSenders) return true;
        else return authorizedSenders[_senderAddress];
    }

    /// @notice Update the contract address containing valid signatories
    function updateSignatoryContract(address _newSignatoryContract) public onlyOwner {
        signatoryContract = IBridgeSignatory(_newSignatoryContract);
        SignatoryContractAddressChanged(signatoryContract);
    }

    function destroy() onlyOwner public {
        selfdestruct(owner);
    }

    /// @notice Withdraw certain amount from the contract
    function withdraw(uint amount) onlyOwner returns (bool) {
        require(amount <= this.balance);
        owner.transfer(amount);
        return true;
    }
}



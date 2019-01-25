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

library AionBridgeHelpers {

    function addressArrayContains(address[] _array, address _value) internal constant returns (bool) {
        for (uint128 i = 0; i < _array.length; i++) {
            if (_array[i] == _value) {
                return true;
            }
        }
        return false;
    }

    /// @param _transferHash Hash of the transfer data to be validated
    /// @param _publicKey Public keys of the signatories who signed the hash
    /// @param _signaturePart1 First 32 bytes of the signatures
    /// @param _signaturePart2 Second 32 bytes of the signatures
    /// @param _signatoryContract Address of the contract containing valid signatories
    /// @return number of valid signatures recovered
    function getValidSignatureCount(
        bytes32 _transferHash,
        bytes32[] _publicKey,
        bytes32[] _signaturePart1,
        bytes32[] _signaturePart2,
        IBridgeSignatory _signatoryContract
    )
        internal
        constant
        returns (uint128)
    {
        //require(_publicKey.length >= _signatoryQuorumSize); -> moved to adapter
        address[] memory recoveredSigners = new address[](_publicKey.length);
        uint128 recoveredSignerCount = 0;

        for (uint128 i = 0; i < _publicKey.length; i++) {
            if (isValidSignature(_transferHash, _publicKey[i], _signaturePart1[i], _signaturePart2[i])) {
                address recoveredAddress = recoverAionAddress(_publicKey[i]);
                if (_signatoryContract.isSignatory(recoveredAddress) && !addressArrayContains(recoveredSigners, recoveredAddress)) {
                    recoveredSigners[recoveredSignerCount] = recoveredAddress;
                    recoveredSignerCount ++;
                }
            }
        }
        return recoveredSignerCount;
    }

    /// @param _transferHash Hash of the transfer data to be validated
    /// @param _publicKey Public keys of the signatories who signed the hash
    /// @param _signaturePart1 First 32 bytes of the signatures
    /// @param _signaturePart2 Second 32 bytes of the signatures
    /// @param _signatoryContract Address of the contract containing valid signatories
    /// @param _quorumSize minimum number of valid signatures required
    /// @return true if _transferHash has been signed by the required number of signatories, false otherwise
    function hasEnoughValidSignatures(
        bytes32 _transferHash,
        bytes32[] _publicKey,
        bytes32[] _signaturePart1,
        bytes32[] _signaturePart2,
        IBridgeSignatory _signatoryContract,
        uint128 _quorumSize
    )
        internal
        constant
        returns (bool)
    {
        //require(_publicKey.length >= _signatoryQuorumSize); -> moved to adapter
        address[] memory recoveredSigners = new address[](_quorumSize);

        for (uint128 i = 0; i < _publicKey.length; i++) {
            if (isValidSignature(_transferHash, _publicKey[i], _signaturePart1[i], _signaturePart2[i])) {
                address recoveredAddress = recoverAionAddress(_publicKey[i]);
                if (_signatoryContract.isSignatory(recoveredAddress) && !addressArrayContains(recoveredSigners, recoveredAddress)) {
                    recoveredSigners[_quorumSize-1] = recoveredAddress;
                     _quorumSize--;
                    if (_quorumSize == 0)
                        return true;
                }
            }
        }
        return false;
    }

    /// @notice verifies the signature
    /// @param _transferHash Hash of the transfer data to be validated
    /// @param _publicKey Public key of the signatory who signed the hash
    /// @param _signaturePart1 First 32 bytes of the signature
    /// @param _signaturePart2 Second 32 bytes of the signature
    /// @return true if _transferHash has been signed by the signatory holding _publicKey, false otherwise
    function isValidSignature(
        bytes32 _transferHash,
        bytes32 _publicKey,
        bytes32 _signaturePart1,
        bytes32 _signaturePart2
    )
        internal
        constant
        returns (bool)
    {
        return edverify(_transferHash, _publicKey, _signaturePart1, _signaturePart2) != address(0);
    }

    /// @notice recover Aion address from the public key
    function recoverAionAddress(bytes32 _publicKey) internal constant returns (address){
        return address(blake2b256(_publicKey)
            & bytes32(0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
            | bytes32(0xa000000000000000000000000000000000000000000000000000000000000000));
    }
}

contract AionBridgeAdapter is Pausable {

    //ETH
    bytes1 constant sourceNetworkId = 0x2;

    IBridgeSignatory public signatoryContract;

    uint128 public maximumBridgeTransactionGas;
    uint128 public transactionFee;
    uint128 requestId;

    address public relayer;
    uint public signatoryQuorumSize; //uint128
    uint128 expectedSourceTransferId;
    bytes20 public sourceAdapterAddress;
    bool public acceptOnlyAuthorizedSenders;

    mapping(address => bool) public authorizedSenders;
    //mapping of transactionHash => blockNumber
    mapping(bytes32 => uint) public processedTransactions;

    //source events
    event BridgeTransferRequested (uint128 indexed _requestId, address indexed _transactionInitiator, bytes20 indexed _recipientContract, uint128 _gas, bytes _data);
    event AuthorizedSenderAdded (address indexed _newAuthorizedSender);
    event TransactionFeeUpdated (uint128 indexed _txFee);

    //destination events
    event Processed (uint128 indexed _sourceTransferId, bytes32 indexed _sourceTransactionHash, address indexed _recipientContract, bytes32 hash, bool result);
    event AlreadyProcessed (uint indexed _blockNumber);
    event RelayerChanged (address indexed _newRelayer);
    event SignatoryQuorumSizeChanged (uint indexed _newSignatoryQuorumSize); //uint128
    event SignatoryContractAddressChanged (address indexed _newSignatoryContract);


    modifier onlyRelayer() {
        require(msg.sender == relayer);
        _;
    }

    modifier onlyAssociatedSourceAdaptor(bytes20 _sourceAdapterAddress) {
        require(sourceAdapterAddress == _sourceAdapterAddress);
        _;
    }

    function AionBridgeAdapter(
        address _signatoryContractAddress,
        address _relayer,
        uint _signatoryQuorumSize, //uint128
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

    /// @notice Processes a message transfer request originated on the Ethereum chain
    /// @dev Each source transaction is processed once and identified using the transaction hash
    /// Additionally, transactions are nonced to keep the order on both chains
    /// @param _sourceTransactionHash Transaction hash from the Ethereum adapter which contains the BridgeTransferRequested event
    /// @param _recipientContract Contract to call from this adapter
    /// @param _data Encoded function call and arguments
    /// @param _gas Amount of gas to be used by the function call
    /// @param _sourceTransferId Nonce of the Ethereum transfer request event
    /// @param _publicKey Public keys of signatories
    /// @param _signaturePart1 First 32 bytes of the signatures
    /// @param _signaturePart2 Second 32 bytes of the signatures
    function processTransfer(
        bytes32 _sourceTransactionHash,
        address _recipientContract,
        bytes _data,
        uint128 _gas,
        uint128 _sourceTransferId,
        bytes32[] _publicKey,
        bytes32[] _signaturePart1,
        bytes32[] _signaturePart2
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
        require(_publicKey.length >= signatoryQuorumSize);

        bytes32 hash = computeTransferHash(_sourceTransactionHash, _recipientContract, _data, _gas, _sourceTransferId);

        require(AionBridgeHelpers.hasEnoughValidSignatures(hash, _publicKey, _signaturePart1, _signaturePart2, signatoryContract, signatoryQuorumSize));

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

    /// @notice Updates the associated Ethereum adapter contract address
    function setSourceAdapterAddress(bytes20 _newAdapterAddress) public onlyOwner {
        sourceAdapterAddress = _newAdapterAddress;
    }

    //uint128
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
    /// @param _sourceTransactionHash Transaction hash from the Ethereum adapter which contains the BridgeTransferRequested event
    /// @param _recipientContract Contract to call from this adapter
    /// @param _data Encoded function call and arguments
    /// @param _gas Amount of gas to be used by the function call
    /// @param _sourceTransferId Nonce of the Ethereum transfer request event
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
        return blake2b256(_sourceTransactionHash, sourceAdapterAddress, _recipientContract, _data, _gas, _sourceTransferId, sourceNetworkId);
    }
    // ----------------------------------

    // ------------- source -------------

    /// @notice Generates a cross chain transfer request event to be picked up by the bridge
    /// @dev Contract owner can define a fee for each transaction relayed to Ethereum
    /// @param _destinationContract Recipient contract address to be called on Ethereum
    /// @param _data Encoded function call and arguments
    /// @param _gas Amount of gas to be used by the function call
    function requestTransfer(
        bytes20 _destinationContract,
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

    /// @notice Updates the maximum amount of gas that can be used on Ethereum to call a function
    function updateMaximumBridgeTransactionGas(uint128 _maximumBridgeTransactionGas) public onlyOwner {
        maximumBridgeTransactionGas = _maximumBridgeTransactionGas;
    }

    /// @notice Updates the fee for relaying each message to Ethereum
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



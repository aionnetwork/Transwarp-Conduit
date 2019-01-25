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

interface IBridgeSignatory {
    function isSignatory(address _signatoryAddress) public constant returns (bool);
    function signatoryCount() public constant returns (uint);
}

contract BridgeSignatory is IBridgeSignatory, Owned {

    string constant network = "Aion-Ethereum";
    uint public minimumVotesRequired;
    bool public initializationMode = true;

    address[] public validSignatories;

    mapping(address => bytes32) public signatoryName;
    mapping(bytes32 => address[]) signedChanges;

    modifier onlyInitializationMode(){
        require(initializationMode);
        _;
    }

    modifier onlySelfGovernanceMode(){
        require(!initializationMode);
        _;
    }

    modifier onlySignatories(){
        require(signatoryName[msg.sender] != 0);
        _;
    }

    modifier signatoryDoesNotExist(address _signatoryAddress) {
        require(signatoryName[_signatoryAddress] == 0);
        _;
    }

    modifier signatoryExists(address _signatoryAddress) {
        require(signatoryName[_signatoryAddress] != 0);
        _;
    }

    event SignatoryAdded(address indexed _signatoryAddress, bytes32 _signatoryName);
    event SignatoryRemoved(address indexed _signatoryAddress, bytes32 _signatoryName);
    event SignatureReceived(address indexed _signatoryAddress, bytes32 _signatoryName, uint _currentVoteCount, uint _minimumVotesRequired, bytes1 _operation);

    function BridgeSignatory(address[] _initialSignatoryAddresses, bytes32[] _initialSignatoryNames){
        require(_initialSignatoryAddresses.length == _initialSignatoryNames.length);
        for (uint i = 0; i < _initialSignatoryAddresses.length; i++) {
            require(isUniqueSignatory(_initialSignatoryAddresses[i], _initialSignatoryNames[i]));
            signatoryName[_initialSignatoryAddresses[i]] = _initialSignatoryNames[i];
            validSignatories.push(_initialSignatoryAddresses[i]);
        }
    }

    function() public payable {
        revert();
    }

    /// @notice Add a new signatory
    /// @dev During the initialization mode only the owner has the authority to add a signatory to the list
    /// Once the self governance mode is initiated signatories will manage themselves
    /// With this implementation, owner can be a signatory
    function addSignatory(address _signatoryAddress, bytes32 _signatoryName)
    public
    onlyOwner
    onlyInitializationMode
    signatoryDoesNotExist(_signatoryAddress)
    {
        addToStorage(_signatoryAddress, _signatoryName);
    }

    /// @notice Remove a signatory
    /// @dev During the initialization mode only the owner has the authority to remove a signatory from the list
    /// Once the self governance mode is initiated signatories will manage themselves
    function removeSignatory(address _signatoryAddress, bytes32 _signatoryName)
    public
    onlyOwner
    onlyInitializationMode
    signatoryExists(_signatoryAddress)
    {
        deleteFromStorage(_signatoryAddress, _signatoryName);
    }

    /// @notice Submit vote to add a new signatory
    /// @dev During the self governance mode, majority of signatories should submit their vote for an action to be performed
    function submitAddSignatoryVote(address _signatoryAddress, bytes32 _signatoryName)
    public
    onlySignatories
    onlySelfGovernanceMode
    signatoryDoesNotExist(_signatoryAddress)
    {
        bytes32 hash = keccak256(_signatoryAddress, _signatoryName, 0x1); //"add"
        signedChanges[hash].push(msg.sender);

        if (signedChanges[hash].length == minimumVotesRequired) {
            //delete form signedChanges because threshold can change
            //need to start from scratch every time voting begins
            delete signedChanges[hash];
            addToStorage(_signatoryAddress, _signatoryName);
        } else {
            SignatureReceived(_signatoryAddress, _signatoryName, signedChanges[hash].length, minimumVotesRequired, 0x1);
        }
    }

    /// @notice Submit vote to remove a signatory
    /// @dev During the self governance mode, majority of signatories should submit their vote for an action to be performed
    function submitRemoveSignatoryVote(address _signatoryAddress, bytes32 _signatoryName)
    public
    onlySignatories
    onlySelfGovernanceMode
    signatoryExists(_signatoryAddress)
    {
        bytes32 hash = keccak256(_signatoryAddress, signatoryName[_signatoryAddress], 0x2); //"remove"
        signedChanges[hash].push(msg.sender);

        if (signedChanges[hash].length == minimumVotesRequired) {
            //delete form signedChanges because threshold can change.
            //need to start from scratch every time voting begins.
            delete signedChanges[hash];
            deleteFromStorage(_signatoryAddress, _signatoryName);
        } else {
            SignatureReceived(_signatoryAddress, signatoryName[_signatoryAddress], signedChanges[hash].length, minimumVotesRequired, 0x2);
        }
    }

    /// @notice Remove the caller from valid signatory list
    /// @dev This is possible in both self governance and initialization modes
    function removeSelfFromSignatoryList()
    public
    onlySignatories
    signatoryExists(msg.sender)
    {
        deleteFromStorage(msg.sender, signatoryName[msg.sender]);
    }

    /// @notice Starts the self governance mode
    /// @dev once the self governance mode is initialized owner does not have the power to add or remove signatories
    /// Mode cannot be reverted back to initialization.
    function initiateSelfGovernanceMode() public  onlyInitializationMode onlyOwner {
        initializationMode = !initializationMode;
    }

    /// @return signatory address associated to the name if it exists
    function lookupName(bytes32 _signatoryName) constant public returns (address) {
        for (uint i = 0; i < validSignatories.length; i++) {
            if (signatoryName[validSignatories[i]] == _signatoryName) {
                return validSignatories[i];
            }
        }
        return address(0);
    }

    /// @return true if the address is a valid signatory, false otherwise
    function isSignatory(address _signatoryAddress) public constant returns (bool) {
        //return AionBridgeUtils.addressArrayContains(validSignatories, _signatoryAddress) == true;
        return signatoryName[_signatoryAddress] != 0;
    }

    /// @return the number of valid signatories registered in the contract
    function signatoryCount() public constant returns (uint) {
        return validSignatories.length;
    }

    /// @return the list of valid signatories registered in the contract
    function getValidSignatoryList() public constant returns (address[] memory) {
        return validSignatories;
    }

    /// @dev Set the minimum number of votes required to add or remove a signatory
    function setMinimumVotesRequired(uint _newValue) private {
        require(_newValue != 0 && _newValue <= validSignatories.length);
        minimumVotesRequired = _newValue;
    }

    /// @notice recalculate the quorum threshold
    /// @dev It is done after each change to the signatory list
    /// Size of the signatory list can never be 0
    function recalculateMinimumVotesRequired() private {
        if (!initializationMode) {
            if (validSignatories.length < 5) {
                setMinimumVotesRequired(validSignatories.length);
            } else {
                // compute majority
                setMinimumVotesRequired(uint((2 * validSignatories.length) / 3));
            }
        }
    }

    /// @notice Remove the signatory from the list
    /// @dev Existence in array has been validated before
    function deleteFromStorage(address _signatoryAddress, bytes32 _signatoryName) private {
        require(signatoryName[_signatoryAddress] == _signatoryName);

        for (uint i = 0; i < validSignatories.length - 1; i++) {
            if (validSignatories[i] == _signatoryAddress) {
                validSignatories[i] = validSignatories[validSignatories.length - 1];
                break;
            }
        }
        validSignatories.length -= 1;
        recalculateMinimumVotesRequired();
        delete signatoryName[_signatoryAddress];

        SignatoryRemoved(_signatoryAddress, _signatoryName);
    }

    /// @notice Add the signatory to list
    function addToStorage(address _signatoryAddress, bytes32 _signatoryName) private {
        require(isUniqueSignatory(_signatoryAddress, _signatoryName));

        signatoryName[_signatoryAddress] = _signatoryName;
        validSignatories.push(_signatoryAddress);
        recalculateMinimumVotesRequired();

        SignatoryAdded(_signatoryAddress, _signatoryName);
    }

    /// @return true if the signatory name and address do not exit in the list, false otherwise
    function isUniqueSignatory(address _signatoryAddress, bytes32 _signatoryName) private constant returns (bool){
        return _signatoryAddress != address(0) && _signatoryName != 0 && lookupName(_signatoryName) == address(0);
    }
}

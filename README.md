
#TWC Contracts #
_**DISCLAIMER:** We do not recommend using these contracts in a production environment. The code has not been fully tested or
                      audited._

Transwarp-Conduit (TWC) is a notary-based protocol for message transfers between two smart-contract enabled blockchain networks. 
The contracts provided in this repository implement the logic to relay generic messages.

 ## Operation  ## 
The TWC bridge node connects two blockchains by listening to the source chain's Adapter contract events and calling the destination adapter. 
Users can call the Adapter contract either through a smart contract or an application with the message details to be transferred. 
TWC node will pick up this event and ask signatories to attest to its history and content. Once enough signatures have been collected, 
the transfer transaction will be submitted to the destination Adapter where it will be validated. 
If the transfer is valid, it will be processed by the contract and the encoded function will be called.

 ## Components  ## 
 **Adapter Contract**

The Adapter contract is the primary interface between the TWC node and the developer defined smart contract (or application).
The core functionality of the Adapter is to:
* Accept incoming messages (encoded function calls) from developer smart contracts or applications through
  `requestTransfer`.

    * Assign a nonce to each transfer and charge usage fees as specified by the owner.  Optionally, it may also verify senders, preventing unauthorized users from initiating cross chain transfers.
    * Emit outgoing message events to be picked up by TWC (_BridgeTransferRequested_)
    
* Accept incoming messages from the TWC node (identified by the Relayer account) through
  `processTransfer`.

    * Verify transfer signatures against the current set of signatories and threshold.
    * Maintain a list of processed messages and reject duplicate messages.
    * Track nonces of previously sent messages and reject out-of-order transfers.
    * Call developer smart contracts.
    * Emit events indicating the transfer status (_Processed/AlreadyProcessed_).
    
 **Signatory Contract**
 
 Signatory contract contains the list of valid signatory addresses and associated names. 
 Signatory's role in this system is to independently verify each event on the source chain and sign the hash of its content. 
 Maintaining valid signatories can be performed using a voting mechanism in this smart contract.
 
  ## Usage  ## 
  This section outlines the steps to deploy and use the TWC adapter contracts.
 
  Prerequisites: 
  * Deploy Adapter contracts on both Aion and Ethereum. For each contract the following should be set:
     * `_signatoryContractAddress`: An address of a contract implementing the `IBridgeSignatory` interface, storing the valid signatory information. 
     * `_relayer`: An account address that will be used by the bridge to call the adapter contract and process transfers. 
     * `_signatoryQuorumSize`: Minimum number of signatures required for a transfer request to be valid. 
     * `_transactionFee`: Fee associated with performing each bridge transaction. 
     * `_acceptOnlyAuthorizedSenders`: Indicate whether only a pre-authorized set of accounts can request a bridge message transfer. 
  * Set the source adapter contract address (`setSourceAdapterAddress`). Aion adapter will store the Eth adapter address and vice versa. 
  * Encoded function in the recipient contract should be accessible by the Adapter contract. Otherwise the function call will fail.
 
 
 Flow to send a cross-chain message transfer transaction is as follows:
 
 * On the source side of the transfer:
 
 1. User picks the destination contract, function name and arguments 
 
 2. A user account or contract calls the `requestTransfer` function with the destination contract address and encoded function call. Optionally the amount of gas that should be used by this function can be set as well. The sender account should be accepted in the adapter contract.  
 
    For example, an encoded function call for _setValue_ can be generated using one of the following ways: 
 
    ```
    function setValue(uint128 _v) { value = _v; } 
    ```
 
    Solidity (v0.4.24): 
    ```
    abi.encodeWithSelector(bytes4(sha3(“setValue(uint128)”)), 1) 
    ```
 
    Web3: 
 
    ``` 
    web3.eth.abi.encodeFunctionCall( 
    
     { "name": "setValue",  
     
       "type": "function",  
       
       "inputs": [{"type": "uint128", "name": "_v"}] 
       
       }, [1]); 
       ``` 
       
    Furthermore, user should include the cross-chain transfer fee (`transactionFee`) in this transaction. 
    If the amount sent is less than the transfer fee, transaction will be rejected. 
    Otherwise the extra value will be transferred back to the user.
    
 * On the Bridge side:   
 If the `requestTransfer` transaction is successful, a _BridgeTransferRequested_ event is generated which includes an associated Id (nonce). 
 Bridge will listen for this event and send a request to signatories asking for signatures. 
 Signatories will validate the occurrence of the event and sign the hash of the transfer data. 
 Hash method is Keccak256 on Ethereum and blake2b256 on Aion. 
 
 ```
 Hash (sourceTransactionHash, sourceAdapterAddress, recipientContract, encodedFunctionCall, gas, sourceTransferId, sourceNetworkId)
 ``` 
 
 Once the required number of signatories have signed the hash, the bridge calls the `processTransfer` function on the destination adapter.
 
 * On the destination side:
 1. The `processTransfer` function is called by the Relayer account through the bridge. 
 2. Adapter contract checks the following conditions: 
    * Transaction hash should not have been processed before. 
    * Id the of the transfer request should be equal to the expected Id or nonce to maintain order between chains. 
    * There should be enough signatures included as the input. 
    * Signatures should be valid 
 3. If the conditions pass,  
    * The recipient contract will be called with the encoded data. 
    * Transaction hash will be marked as processed. 
    * An event will be generated indicating the success of the transaction and the status of the function call. 
    ```
    event Processed (uint128 indexed _sourceTransferId, bytes32 indexed _sourceTransactionHash, address indexed _recipientContract, bytes32 hash, bool result);
    ```
 4. If the transaction hash has been processed before, an event is generated which includes the block number in which the original `processTransfer` transaction was sealed. 
    This can be used to track the original transaction and ensure it's finalized.
    ``` 
    event AlreadyProcessed (uint indexed _blockNumber);
    ```
 5. In other fail cases, transaction will be reverted.
 
 - - - -
 See [TWC paper link] for more details.
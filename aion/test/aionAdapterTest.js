#!/usr/bin/env nodejs
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

const fs = require('fs');
const cnf = require('./config.js');

const sol = fs.readFileSync(__dirname + '/../AionBridgeContracts_flat.sol', {
    encoding: 'utf8'
});

let owner = cnf.ownerAccount;
let ownerPrivateKey = cnf.ownerPrivateKey;

let bridgeAdapterAddr, bridgeAdapterAbi, bridgeAdapterCode, bridgeAdapterInst;
let signatoryAbi, signatoryCode, signatoryAddr;
let EthAdapterAddress = '0xbd1726746aacd801b2a750572aca8c1742d43d73';
/*
 * sig required = 1
 * max gas: 1000000
 * fee 100
 */
let initialSignatories = [
    'a0eb56d95816b918e727ce7c2a1b4457743c2bc1e9a6816211a49c269c6175c2',
    'a03e93dbcbb537a7fb7b0074767c1c285ef0560f8d9a3338e154ebfd4a720d51',
    'a07c95cc8729a0503c5ad50eb37ec8a27cd22d65de3bb225982ec55201366920',
    'a0e6a0c9c85db355fdceccc44444618b3213b3d5c3c3e26dcfe039ed07f310cd',
    'a08849e680dbede69077b3be7d9c8c37f5849c46cce63eafb26bd2083ce32a48'];
let initialNames = [
    'Aion1',
    'Aion2',
    'MN',
    'Micro',
    'Aion3'
];

//todo: add authorized sender test

let aionRecipient = '0xa0b097956958e5257293d990fd3136fdf4100a8581197edd637a879db37f5010';
let ethRecipient = '0xf2b31e5768871b3ad8435edb2c54b8683a3d1a5a';
let encodedFunctionCall = web3.eth.abi.encodeFunctionCall({"constant": false, "inputs": [{"name": "iteration", "type": "int128"}], "name": "heavyComputation", "outputs": [], "payable": false, "type": "function", "stateMutability": "nonpayable"}, [1]);

describe('AionBridgeAdapter_test as destination adapter', () => {
    before('compile contract', (done) => {
        compile(web3, sol).then((res) => {
            bridgeAdapterAbi = res.AionBridgeAdapter.info.abiDefinition;
            bridgeAdapterCode = res.AionBridgeAdapter.code;
            signatoryAbi = res.BridgeSignatory.info.abiDefinition;
            signatoryCode = res.BridgeSignatory.code;
            done();
        })
    });

    it('deploy contract', (done) => {
        console.log('deploy signatory:');
        deploy(web3, owner, ownerPrivateKey, signatoryAbi, signatoryCode, [initialSignatories, initialNames])
            .then((addr) => {
            signatoryAddr = addr;
            console.log('deploy adapter:');
            deploy(web3, owner, ownerPrivateKey, bridgeAdapterAbi, bridgeAdapterCode,
                [signatoryAddr, cnf.relayerAddress, 1, 1000000, 100, false])
                .then((addr) => {
                    bridgeAdapterAddr = addr;
                    bridgeAdapterInst = new web3.eth.Contract(bridgeAdapterAbi, bridgeAdapterAddr);
                    done();
                }, (err) => {
                    done(err);
                });
        })

    }).timeout(0);

    it('set source adapter address', (done) => {
        let txCall = {
            to: bridgeAdapterAddr,
            gas: 400000,
            data: bridgeAdapterInst.methods.setSourceAdapterAddress(EthAdapterAddress).encodeABI()
        };

        web3.eth.accounts.signTransaction(txCall, ownerPrivateKey)
            .then((signedTx) => {
                web3.eth.sendSignedTransaction(signedTx.rawTransaction)
                    .then((receipt) => {
                        expect(receipt.status).to.equal(true);
                        done();
                    });
            })
    }).timeout(0);

    it('process new transfer with transferId = 0', (done) => {
        //100k gas
        let txHash = '0x9b726496eb86aad17802c88cfab91047b4197cc0d8560a901b76058f9ff06f8e';
        let txCall = {
            to: bridgeAdapterAddr,
            gas: 400000,
            data: bridgeAdapterInst.methods.processTransfer(
                txHash, //tx hash
                aionRecipient, //aionRecipient
                encodedFunctionCall,
                100000, //gas
                0, //transferId
                ['19ab2f3355c2f74376718c3f6c96a779de2144c4592a5cab23c82b739dc44fe0'],
                ['599cb2dc90955f5af772261f3306db29733dd21b9ccff206b2579f5f65afa2df'],
                ['7a8df321da759cd049125fb6b4be48813cce1602857942ea67cb823f6d847904']).encodeABI()
        };

        web3.eth.accounts.signTransaction(txCall, cnf.relayerPrivateKey)
            .then((signedTx) => {
                web3.eth.sendSignedTransaction(signedTx.rawTransaction)
                    .then((receipt) => {
                        if (cnf.debugLevelLogging)
                            console.log("process transfer receipt", receipt);
                        expect(receipt.status).to.equal(true);
                        expect(parseInt(receipt.logs[0].topics[1], 16)).to.equal(0);
                        expect(receipt.logs[0].topics[2].toLowerCase()).to.equal(txHash);
                        expect(receipt.logs[0].topics[3].toLowerCase()).to.equal(aionRecipient);
                        bridgeAdapterInst.methods.processedTransactions(txHash).call()
                            .then((res) => {
                                expect(res).to.equal(receipt.blockNumber.toString());
                                done();
                            });
                    });
            })
    }).timeout(0);

    it('process new transfer with transferId = 1', (done) => {
        //100k gas
        let txHash = '0x4284c96c20a1057f26346a60ee493f7442afd9ed038a3d93126a3203a24b33b9';
        let txCall = {
            to: bridgeAdapterAddr,
            gas: 400000,
            data: bridgeAdapterInst.methods.processTransfer(
                txHash, //tx hash
                aionRecipient, //aionRecipient
                encodedFunctionCall,
                100000, //gas
                1, //transferId
                ['19ab2f3355c2f74376718c3f6c96a779de2144c4592a5cab23c82b739dc44fe0'],
                ['f84899d2a53e7f916a3bbc92f706c8add6c169857b153c91a934c48d029a5a65'],
                ['652340cedae32fff0c521cceaaf2a4123dd7f6f9719216e936d9308493015d01']).encodeABI()
        };

        web3.eth.accounts.signTransaction(txCall, cnf.relayerPrivateKey)
            .then((signedTx) => {
                web3.eth.sendSignedTransaction(signedTx.rawTransaction)
                    .then((receipt) => {
                        if (cnf.debugLevelLogging)
                            console.log("process transfer receipt", receipt);
                        expect(receipt.status).to.equal(true);
                        expect(parseInt(receipt.logs[0].topics[1], 16)).to.equal(1);
                        expect(receipt.logs[0].topics[2].toLowerCase()).to.equal(txHash);
                        expect(receipt.logs[0].topics[3].toLowerCase()).to.equal(aionRecipient);
                        bridgeAdapterInst.methods.processedTransactions(txHash).call()
                            .then((res) => {
                                expect(res).to.equal(receipt.blockNumber.toString());
                                done();
                            });
                    });
            })
    }).timeout(0);

    it('process transfer with a transaction hash already included should emit the block number', (done) => {
        //100k gas
        let txHash = '0x9b726496eb86aad17802c88cfab91047b4197cc0d8560a901b76058f9ff06f8e';
        let txCall = {
            to: bridgeAdapterAddr,
            gas: 400000,
            data: bridgeAdapterInst.methods.processTransfer(
                txHash, //tx hash
                aionRecipient, //aionRecipient
                encodedFunctionCall,
                100000, //gas
                2, //transferId
                ['19ab2f3355c2f74376718c3f6c96a779de2144c4592a5cab23c82b739dc44fe0'],
                ['599cb2dc90955f5af772261f3306db29733dd21b9ccff206b2579f5f65afa2df'],
                ['7a8df321da759cd049125fb6b4be48813cce1602857942ea67cb823f6d847904']).encodeABI()
        };

        web3.eth.accounts.signTransaction(txCall, cnf.relayerPrivateKey)
            .then((signedTx) => {
                web3.eth.sendSignedTransaction(signedTx.rawTransaction)
                    .then((receipt) => {
                        if (cnf.debugLevelLogging)
                            console.log("process transfer receipt", receipt);
                        expect(receipt.status).to.equal(true);
                        expect(parseInt(receipt.logs[0].topics[1], 16)).to.be.above(0);
                        done();
                    });
            })
    }).timeout(0);

    it('transfer with a wrong id should fail', (done) => {

        let txHash = '0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
        let txCall = {
            to: bridgeAdapterAddr,
            gas: 400000,
            data: bridgeAdapterInst.methods.processTransfer(
                txHash, //tx hash
                aionRecipient, //aionRecipient
                encodedFunctionCall,
                100000, //gas
                1, //transferId
                ['19ab2f3355c2f74376718c3f6c96a779de2144c4592a5cab23c82b739dc44fe0'],
                ['59f5d1d4b0ea8b744886bc7905443425410f812a36344cbc3c097c6a15792ef7'],
                ['5663638d130ea789d4362c78104bf68fa9896e1563f7643afa0cc715a9618a0a']).encodeABI()
        };

        web3.eth.accounts.signTransaction(txCall, cnf.relayerPrivateKey)
            .then((signedTx) => {
                web3.eth.sendSignedTransaction(signedTx.rawTransaction)
                    .on('receipt', (receipt) => {
                        expect(receipt.status).to.equal(false);
                    })
                    .on('error', () => {
                        done();
                    });
            })
    }).timeout(0);

    it('incrementing required number of signatures', (done) => {
        let newQuorumSize = 2;
        let txCall = {
            to: bridgeAdapterAddr,
            gas: 400000,
            data: bridgeAdapterInst.methods.updateSignatoryQuorumSize(newQuorumSize).encodeABI()
        };

        web3.eth.accounts.signTransaction(txCall, ownerPrivateKey)
            .then((signedTx) => {
                web3.eth.sendSignedTransaction(signedTx.rawTransaction)
                    .then((receipt) => {
                        expect(receipt.status).to.equal(true);
                        expect(parseInt(receipt.logs[0].topics[1], 16)).to.equal(newQuorumSize);
                        done();
                    });
            })
    }).timeout(0);

    it('transfer without sufficient signatures should fail', (done) => {
        let txHash = '0x4e2cb05ef2f8b824e181b75087d94918c938d29c1e0f6e5f3f93dc84420ca6d8';
        let txCall = {
            to: bridgeAdapterAddr,
            gas: 400000,
            data: bridgeAdapterInst.methods.processTransfer(
                txHash, //tx hash
                aionRecipient, //aionRecipient
                encodedFunctionCall,
                100000, //gas
                2, //transferId
                ['19ab2f3355c2f74376718c3f6c96a779de2144c4592a5cab23c82b739dc44fe0'],
                ['083e161067f54347eeba504be550f6542390ee22e7e05898b1584b9545a44c6b'],
                ['b0d0a2126ad9185eda272a9e056bf29ba80f49809104d1aa0d0d5aa8d0eb1d0e']).encodeABI()
        };

        web3.eth.accounts.signTransaction(txCall, cnf.relayerPrivateKey)
            .then((signedTx) => {
                web3.eth.sendSignedTransaction(signedTx.rawTransaction)
                    .on('receipt', (receipt) => {
                        expect(receipt.status).to.equal(false);
                    })
                    .on('error', () => {
                        done();
                    });
            })
    }).timeout(0);

    it('process new transfer with 2 unique signatures should succeed', (done) => {
        //100k gas
        let txHash = '0x4e2cb05ef2f8b824e181b75087d94918c938d29c1e0f6e5f3f93dc84420ca6d8';
        let txCall = {
            to: bridgeAdapterAddr,
            gas: 400000,
            data: bridgeAdapterInst.methods.processTransfer(
                txHash, //tx hash
                aionRecipient, //aionRecipient
                encodedFunctionCall,
                100000, //gas
                2, //transferId
                ['19ab2f3355c2f74376718c3f6c96a779de2144c4592a5cab23c82b739dc44fe0', '0226f8cd418919e268c7450d212e3700abe6db0201dcb7965a95396df9b3e74f'],
                ['083e161067f54347eeba504be550f6542390ee22e7e05898b1584b9545a44c6b', 'c01455133bfd7ec2e3be3b4a68637ebf569ed346f4456d6214564cd6de13d8eb'],
                ['b0d0a2126ad9185eda272a9e056bf29ba80f49809104d1aa0d0d5aa8d0eb1d0e', '96400f36eefee2537d9a1f2f76c8491e4d604fffbfa9d83659b9d01a3b1a2d0f']).encodeABI()
        };

        web3.eth.accounts.signTransaction(txCall, cnf.relayerPrivateKey)
            .then((signedTx) => {
                web3.eth.sendSignedTransaction(signedTx.rawTransaction)
                    .then((receipt) => {
                        if (cnf.debugLevelLogging)
                            console.log("process transfer receipt", receipt);
                        expect(receipt.status).to.equal(true);
                        expect(parseInt(receipt.logs[0].topics[1], 16)).to.equal(2);
                        expect(receipt.logs[0].topics[2].toLowerCase()).to.equal(txHash);
                        expect(receipt.logs[0].topics[3].toLowerCase()).to.equal(aionRecipient);
                        bridgeAdapterInst.methods.processedTransactions(txHash).call()
                            .then((res) => {
                                expect(res).to.equal(receipt.blockNumber.toString());
                                done();
                            });
                    });
            })
    }).timeout(0);

    it('process new transfer with 2 valid signatures and 2 invalid signatures should succeed', (done) => {
        //100k gas
        let txHash = '0x6f5bcd308ab2e02dae1dae19f5488a2cf4bb5a7e1fa191b38cd008b191a2a57e';
        let txCall = {
            to: bridgeAdapterAddr,
            gas: 400000,
            data: bridgeAdapterInst.methods.processTransfer(
                txHash, //tx hash
                aionRecipient, //aionRecipient
                encodedFunctionCall,
                100000, //gas
                3, //transferId
                ['2a80540535d30c63024afbc491efac24f40ccfbc5c81bc1babb81bcb8da23166', '19ab2f3355c2f74376718c3f6c96a779de2144c4592a5cab23c82b739dc44fe0', '19ab2f3355c2f74376718c3f6c96a779de2144c4592a5cab23c82b739dc44fe0', '0226f8cd418919e268c7450d212e3700abe6db0201dcb7965a95396df9b3e74f'],
                ['d52210022821b0408717face4a5b054d2f25b9925279c70c4de576a08a058367', '49ce0833bf7d8f65aa6439d835c3751d9ba853a534262eac5f968af28ee8e15b', '49ce0833bf7d8f65aa6439d835c3751d9ba853a534262eac5f968af28ee8e15b', '5ded63db24349da1b92f951ac9162e373597f9548da2a9265d71e5fff2978e22'],
                ['b03c00a785589ad7f650700cefe4c2530286d1a2d7268fe8582e5244bf307c0d', 'f37cb7168d583d295deb2abbae77a8355beac287f9e8f2855814012693ab140a', 'f37cb7168d583d295deb2abbae77a8355beac287f9e8f2855814012693ab140a', '4c4ea1623616184517f0edb9fc34757f4a2b38ad3e4c761cbd40683c9aec4809']
            ).encodeABI()
        };

        web3.eth.accounts.signTransaction(txCall, cnf.relayerPrivateKey)
            .then((signedTx) => {
                web3.eth.sendSignedTransaction(signedTx.rawTransaction)
                    .then((receipt) => {
                        if (cnf.debugLevelLogging)
                            console.log("process transfer receipt", receipt);
                        expect(receipt.status).to.equal(true);
                        expect(parseInt(receipt.logs[0].topics[1], 16)).to.equal(3);
                        expect(receipt.logs[0].topics[2].toLowerCase()).to.equal(txHash);
                        expect(receipt.logs[0].topics[3].toLowerCase()).to.equal(aionRecipient);
                        bridgeAdapterInst.methods.processedTransactions(txHash).call()
                            .then((res) => {
                                expect(res).to.equal(receipt.blockNumber.toString());
                                done();
                            });
                    });
            })
    }).timeout(0);

    // it('compute hash', (done) => {
    //
    //     bridgeAdapterInst.methods.computeTransferHash(
    //         '0x9b726496eb86aad17802c88cfab91047b4197cc0d8560a901b76058f9ff06f8e',
    //         aionRecipient,
    //         encodedFunctionCall,
    //         100000, 0
    //     ).call()
    //         .then((res) => {
    //             console.log(res);
    //             done();
    //         });
    // }).timeout(0)
    //
    //web3.eth.abi.decodeParameters(typesArray, hexString);
});

describe('AionBridgeAdapter_test as source adapter', () => {

    it('request transfer', (done) => {
        let txCall = {
            to: bridgeAdapterAddr,
            gas: 400000,
            value: 100,
            data: bridgeAdapterInst.methods.requestTransfer(
                ethRecipient, // ethRecipient
                encodedFunctionCall,
                100000 //gas
            ).encodeABI()
        };

        web3.eth.accounts.signTransaction(txCall, cnf.relayerPrivateKey)
            .then((signedTx) => {
                web3.eth.sendSignedTransaction(signedTx.rawTransaction)
                    .then((receipt) => {
                        if (cnf.debugLevelLogging)
                            console.log("request transfer receipt", receipt);
                        expect(receipt.status).to.equal(true);
                        expect(parseInt(receipt.logs[0].topics[1], 16)).to.equal(0);
                        expect(receipt.logs[0].topics[2].toLowerCase()).to.equal(cnf.relayerAddress);
                        expect(receipt.logs[0].topics[3].toLowerCase()).to.equal(ethRecipient.padEnd(66, '0'));
                        web3.eth.getBalance(bridgeAdapterAddr).then((bal) => {
                            expect(parseInt(bal, 10)).to.equal(100);
                            done();
                        })
                    })

            });
    }).timeout(0);

    it('new transfer request should increment the transfer_id', (done) => {
        let txCall = {
            to: bridgeAdapterAddr,
            gas: 400000,
            value: 105,
            data: bridgeAdapterInst.methods.requestTransfer(
                ethRecipient, // ethRecipient
                encodedFunctionCall,
                100000 //gas
            ).encodeABI()
        };

        web3.eth.accounts.signTransaction(txCall, cnf.relayerPrivateKey)
            .then((signedTx) => {
                web3.eth.sendSignedTransaction(signedTx.rawTransaction)
                    .then((receipt) => {
                        if (cnf.debugLevelLogging)
                            console.log("request transfer receipt", receipt);
                        expect(receipt.status).to.equal(true);
                        expect(parseInt(receipt.logs[0].topics[1], 16)).to.equal(1);
                        expect(receipt.logs[0].topics[2].toLowerCase()).to.equal(cnf.relayerAddress);
                        expect(receipt.logs[0].topics[3].toLowerCase()).to.equal(ethRecipient.padEnd(66, '0'));
                        web3.eth.getBalance(bridgeAdapterAddr).then((bal) => {
                            expect(parseInt(bal, 10)).to.equal(200);
                            done();
                        })
                    })
            });
    }).timeout(0);

    it('request transfer with a low fee should fail', (done) => {
        let txCall = {
            to: bridgeAdapterAddr,
            gas: 400000,
            value: 10,
            data: bridgeAdapterInst.methods.requestTransfer(
                ethRecipient, // ethRecipient
                encodedFunctionCall,
                100000 //gas
            ).encodeABI()
        };

        web3.eth.accounts.signTransaction(txCall, cnf.relayerPrivateKey)
            .then((signedTx) => {
                web3.eth.sendSignedTransaction(signedTx.rawTransaction)
                    .on('error', () => {
                        done();
                    })
            });
    }).timeout(0);

    it('update transaction fee', (done) => {
        let txCall = {
            to: bridgeAdapterAddr,
            gas: 400000,
            data: bridgeAdapterInst.methods.updateTransactionFee("1000000000000000000").encodeABI()
        };

        web3.eth.accounts.signTransaction(txCall, ownerPrivateKey)
            .then((signedTx) => {
                web3.eth.sendSignedTransaction(signedTx.rawTransaction)
                    .then((receipt) => {
                        expect(parseInt(receipt.logs[0].topics[1], 16)).to.equal(1000000000000000000);
                        done();
                    })
            });
    }).timeout(0);

    it('withdraw', async () => {
        let txCall = {
            to: bridgeAdapterAddr,
            gas: 400000,
            value: 1000000000000000000,
            data: bridgeAdapterInst.methods.requestTransfer(
                ethRecipient, // ethRecipient
                encodedFunctionCall,
                100000 //gas
            ).encodeABI()
        };

       let signedTx = await web3.eth.accounts.signTransaction(txCall, cnf.relayerPrivateKey);
       let transferRequestTx = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

        txCall = {
            to: bridgeAdapterAddr,
            gas: 400000,
            data: bridgeAdapterInst.methods.withdraw("1000000000000000000").encodeABI()
        };

        let ownerOldBalance = new BigNumber(await web3.eth.getBalance(owner), 10);
        signedTx = await web3.eth.accounts.signTransaction(txCall, cnf.ownerPrivateKey);
        await web3.eth.sendSignedTransaction(signedTx.rawTransaction);
        let ownerNewBalance = new BigNumber(await web3.eth.getBalance(owner), 10);
        expect(ownerNewBalance.isGreaterThan(ownerOldBalance)).to.equal(true);
        if (cnf.debugLevelLogging) {
            console.log('old balance', ownerOldBalance.shiftedBy(-18).toString());
            console.log('new balance after withdrawal of 1 Aion', ownerNewBalance.shiftedBy(-18).toString());
        }

    }).timeout(0);

    it('sending a transfer request to a paused contract should fail', async () => {
        let txCall = {
            to: bridgeAdapterAddr,
            gas: 400000,
            data: bridgeAdapterInst.methods.pause().encodeABI()
        };

        let signedTx = await web3.eth.accounts.signTransaction(txCall, ownerPrivateKey);
        let tx = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);
        console.log(tx);
        txCall = {
            to: bridgeAdapterAddr,
            gas: 400000,
            value: 100,
            data: bridgeAdapterInst.methods.requestTransfer(
                ethRecipient, // ethRecipient
                encodedFunctionCall,
                100000 //gas
            ).encodeABI()
        };
        signedTx = await web3.eth.accounts.signTransaction(txCall, cnf.relayerPrivateKey);
        web3.eth.sendSignedTransaction(signedTx.rawTransaction).on('error', () => {

        })
    }).timeout(0)
});


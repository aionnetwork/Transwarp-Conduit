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

const sol = fs.readFileSync(__dirname + '/../AionSignatoryDNS.sol', {
    encoding: 'utf8'
});

let owner = cnf.ownerAccount;
let ownerPrivateKey = cnf.ownerPrivateKey;

let signatoryAddr, signatoryAbi, signatoryCode, signatoryInst;

let initialAddresses = [
    '0xa0eb56d95816b918e727ce7c2a1b4457743c2bc1e9a6816211a49c269c6175c2',
    '0xa025f4fd54064e869f158c1b4eb0ed34820f67e60ee80a53b469f725efc06378',
    '0xa0e6a0c9c85db355fdceccc44444618b3213b3d5c3c3e26dcfe039ed07f310cd'];
let initialNames = [
    'Aion',
    'Com',
    'Corp1'
];

let newSignatory = {address: '0xa07c95cc8729a0503c5ad50eb37ec8a27cd22d65de3bb225982ec55201366920', name: 'NS'};

describe('signatory_test', () => {
    before('compile contract', (done) => {
        compile(web3, sol).then((res) => {
            signatoryAbi = res.BridgeSignatory.info.abiDefinition;
            signatoryCode = res.BridgeSignatory.code;
            done();
        })
    });

    it('deploy contract', (done) => {
        deploy(web3, owner, ownerPrivateKey, signatoryAbi, signatoryCode, [initialAddresses, initialNames])
            .then((addr) => {
                signatoryAddr = addr;
                signatoryInst = new web3.eth.Contract(signatoryAbi, signatoryAddr);
                done();
            }, (err) => {
                done(err);
            });

    }).timeout(0);

    it('initial state should be valid', async () => {
        expect(await signatoryInst.methods.initializationMode().call()).to.equal(true);
        expect(await signatoryInst.methods.signatoryCount().call()).to.equal(initialAddresses.length.toString());
        let validSignatories = (await signatoryInst.methods.getValidSignatoryList().call()).map(v => v.toLowerCase());
        expect(validSignatories).to.eql(initialAddresses);
        for (let i = 0; i < initialAddresses.length; i++) {
            expect(await signatoryInst.methods.isSignatory(initialAddresses[i]).call()).to.equal(true);
            expect((await signatoryInst.methods.lookupName(initialNames[i]).call()).toLowerCase()).to.equal(initialAddresses[i]);
        }
    });

    it('owner should be able to add new signatory during initialization mode', (done) => {
        let txCall = {
            to: signatoryAddr,
            gas: 400000,
            data: signatoryInst.methods.addSignatory(newSignatory.address, newSignatory.name).encodeABI()
        };

        web3.eth.accounts.signTransaction(txCall, cnf.ownerPrivateKey)
            .then((signedTx) => {
                    web3.eth.sendSignedTransaction(signedTx.rawTransaction)
                        .then((receipt) => {
                            if (cnf.debugLevelLogging)
                                console.log("add signatory receipt", receipt);
                            expect(receipt.status).to.equal(true);
                            expect(receipt.logs[0].topics[1]).to.equal(newSignatory.address);
                            expect(receipt.logs[0].data).to.equal(web3.utils.padRight(web3.utils.asciiToHex(newSignatory.name), 64));
                            signatoryInst.methods.isSignatory(newSignatory.address).call()
                                .then((res) => {
                                    expect(res).to.equal(true);
                                    done();
                                });
                        });
                })
    }).timeout(0);

    it('owner should be able to remove an existing signatory during initialization mode', (done) => {
        let txCall = {
            to: signatoryAddr,
            gas: 400000,
            data: signatoryInst.methods.removeSignatory(newSignatory.address, newSignatory.name).encodeABI()
        };

        web3.eth.accounts.signTransaction(txCall, cnf.ownerPrivateKey)
            .then((signedTx) => {
                    web3.eth.sendSignedTransaction(signedTx.rawTransaction)
                        .then((receipt) => {
                            if (cnf.debugLevelLogging)
                                console.log("remove signatory receipt", receipt);
                            expect(receipt.status).to.equal(true);
                            expect(receipt.logs[0].topics[1]).to.equal(newSignatory.address);
                            expect(receipt.logs[0].data).to.equal(web3.utils.padRight(web3.utils.asciiToHex(newSignatory.name), 64));
                            signatoryInst.methods.isSignatory(newSignatory.address).call()
                                .then((res) => {
                                    expect(res).to.equal(false);
                                    done();
                                });
                        });
                })
    }).timeout(0);

    it('adding signatory from non-owner account should fail', (done) => {
        let txCall = {
            to: signatoryAddr,
            gas: 400000,
            data: signatoryInst.methods.addSignatory(newSignatory.address, newSignatory.name).encodeABI()
        };

        web3.eth.accounts.signTransaction(txCall, '0x90cd653b7f5e6e26a1fe3f527b0fb417c93d6055300dd96bac2075c285bb398cd725c8766d786fecdf974848659a90ab3b2a10aef0708b8e2a9f1c44cf6e081f')
            .then((signedTx) => {
                web3.eth.sendSignedTransaction(signedTx.rawTransaction)
                    .on('receipt', (receipt) => {
                        expect(receipt.status).to.equal(false);
                    })
                    .on('error', () => {
                        signatoryInst.methods.isSignatory(newSignatory.address).call()
                            .then((res) => {
                                expect(res).to.equal(false);
                                done();
                            });
                    });
            })
    }).timeout(0);

});



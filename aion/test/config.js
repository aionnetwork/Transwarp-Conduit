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
const Web3 = require('aion_web3');
module.exports.provider = "http://localhost:8545";
global.web3 = new Web3(new Web3.providers.HttpProvider(this.provider));


//owner of the contracts. Responsible for initialization
module.exports.ownerAccount = '';
module.exports.ownerPrivateKey = '';

//account responsible for sending process transfer requests to adapter
module.exports.relayerAddress = '';
module.exports.relayerPrivateKey = '';

//view additional info regarding transactions and receipts
module.exports.debugLevelLogging = true;

global.compile = require('./compile.js');
global.deploy = require('./deploy.js');
global.expect = require("chai").expect;
global.BigNumber = require('bignumber.js');
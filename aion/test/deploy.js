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
module.exports = function(w3, acc, privateKey, abi, code, args){
    return new Promise((resolve, reject)=>{
        const deploy = new w3.eth.Contract(abi).deploy({ data: code, arguments: args}).encodeABI();
        w3.eth.accounts.signTransaction({from: acc, gas: 4699999, data: deploy}, privateKey).then((res) => {
            web3.eth.sendSignedTransaction( res.rawTransaction)
                .on('receipt', (receipt) => {
                console.log("deploy txHash =", receipt.transactionHash,
                    "\ncontractAddress =", receipt.contractAddress);
                resolve(receipt.contractAddress)
            }).on('error', (err) => {console.log(err); reject(err)})
    })
})
};
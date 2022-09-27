// const { web3 } = require("hardhat");
const Web3 = require("web3");
const fs = require("fs");
const gToken = require("./abis/gToken");
const liquidator = require("./abis/LiquidationKeeper");
const {ethers} = require("hardhat");

//const Web3_bsc = new Web3("https://bsc-dataseed1.binance.org:443"); //PRODUCTION
const Web3_bsc = new Web3("https://data-seed-prebsc-1-s1.binance.org:8545"); //TEST

const ADDRESS_GTOKEN_1 = "0x8009c10964e1711ADa8f012F59492279d3E33B67"; //gETH
const ADDRESS_GTOKEN_2 = "0x205A69E74dB750e05fB3be0A2f9b8CcbaEcD4B0E"; //gBTC
const ADDRESS_GTOKEN_3 = "0x549f9dcA699217A4FC009d3a654a60Df08c7cfDb"; //gBUSD
const ADDRESS_LIQUIDATOR = "0x31A8379e1131252656842591596995b71A2621A7"; //gBUSD
//const FROM_BLOCK = "18610000";
//const FROM_BLOCK = "14185612"; //"18610000";
//const TO_BLOCK = "14186112"; //"18615000";
//const TO_BLOCK = "14190612";//"18615000";
//const TO_BLOCK = "18615000";

const contract1 = new Web3_bsc.eth.Contract(gToken, ADDRESS_GTOKEN_1);
const contract2 = new Web3_bsc.eth.Contract(gToken, ADDRESS_GTOKEN_2);
const contract3 = new Web3_bsc.eth.Contract(gToken, ADDRESS_GTOKEN_3);
const contract_liquidator = new Web3_bsc.eth.Contract(liquidator, ADDRESS_LIQUIDATOR);

//console.log(toTimestamp('01/07/2022 00:00:00'));
let map = new Map();
let addresses = [];
let amounts = [];

const startTimeStamp = toTimestamp('01/08/2022 00:00:00');
const endTimeStamp = startTimeStamp + 86400;

function toTimestamp(strDate){
  var datum = Date.parse(strDate);
  return datum/1000;
}

function eToNumber(num) {
  let sign = "";
  (num += "").charAt(0) == "-" && (num = num.substring(1), sign = "-");
  let arr = num.split(/[e]/ig);
  if (arr.length < 2) return sign + num;
  let dot = (.1).toLocaleString().substr(1, 1), n = arr[0], exp = +arr[1],
      w = (n = n.replace(/^0+/, '')).replace(dot, ''),
      pos = n.split(dot)[1] ? n.indexOf(dot) + exp : w.length + exp,
      L   = pos - w.length, s = "" + BigInt(w);
  w   = exp >= 0 ? (L >= 0 ? s + "0".repeat(L) : r()) : (pos <= 0 ? "0" + dot + "0".repeat(Math.abs(pos)) + s : r());
  L= w.split(dot); if (L[0]==0 && L[1]==0 || (+w==0 && +s==0) ) w = 0; //** added 9/10/2021
  return sign + w;
  function r() {return w.replace(new RegExp(`^(.{${pos}})(.)`), `$1${dot}$2`)}
}

async function main() {

    let borrowersList = JSON.parse(fs.readFileSync('./borrowers_crawler/borrowers.json', 'utf-8'));
    let INITIAL_BLOCK = 22947909;
    let FINAL_BLOCK = await Web3_bsc.eth.getBlockNumber();

    console.log(borrowersList);
    //borrowersList = await ScanBorrowers(borrowersList,INITIAL_BLOCK,FINAL_BLOCK);



    //const LiquidationKeeper = await ethers.getContractFactory("LiquidationKeeper");
    //const liquidationKeeper = await LiquidationKeeper.attach("0xd0978fe00B6C63A2747664d2a1D3934c855BB378");

    //for (var i = 0; i < borrowersList.length; i++)
    {
        //TODO revisar Jose
        console.log(contract_liquidator.methods.getBorrowerTotalDebts(borrowersList[0]).call());
    }
    //await liquidationKeeper.maxLiquidatableAmount(address borrower); //indica si s'ha de liquidar a X persona
    //await liquidationKeeper.getLiquidatableBorrowerData(address borrower); //aconsegueix què es pot liquidar de x persona
    //var correctLiquidation = await liquidationKeeper.liquidateBorrower(address borrower, address collateral, address gTokenToLiquidate); //liquida a x persona


    fs.writeFileSync('./borrowers_crawler/borrowers.json', JSON.stringify(borrowersList));



  /*while((await Web3_bsc.eth.getBlock(TO_BLOCK)).timestamp<startTimeStamp+86400)
  {
      console.log(TO_BLOCK,(await Web3_bsc.eth.getBlock(TO_BLOCK)).timestamp,startTimeStamp+86400);
      TO_BLOCK++;
  }
  console.log((await Web3_bsc.eth.getBlock(FROM_BLOCK)).timestamp);
  console.log(startTimeStamp+86400);
  console.log((await Web3_bsc.eth.getBlock(TO_BLOCK)).timestamp);
  console.log();
  console.log(TO_BLOCK);*/

  /*for (var i = 0; i < events.length; i++) {
      const timestamp = (await Web3_bsc.eth.getBlock(events[i].blockNumber)).timestamp;
  }*/



  /* aqui tienes un ejemplo de como llamar a otro contrato
  const resultadoFunction = await contract2.nombreFunction(param1, param2)*/
  /*  console.log(addresses.length);

  for (var i = 0; i < addresses.length; i++) {
      console.log(addresses[i],",");
  }*/

  /*for (var i = 0; i < addresses.length; i++) {
      //console.log(eToNumber(map.get(addresses[i])),",");
      amounts.push((map.get(addresses[i])));
      //let ten =new BigNumber(map.get(addresses[i]));
      //console.log(ten.toString());
  }*/

    /*for (var i = 0; i < addresses.length; i++) {
        console.log(eToNumber(amounts[i]),",");
    }*/

  //await contract2.SwapRewardRegisterUser(0,addresses,amounts);
    //var account = Web3_bsc.eth.accounts[0];
  //console.log(account);
  //await contract2.methods.SwapRewardRegisterUsers(0,addresses,amounts).send({from:account});
}
async function ScanBorrowers(borrowersList,INITIAL_BLOCK,FINAL_BLOCK) {
    try {
        var FROM_BLOCK = INITIAL_BLOCK;
        var TO_BLOCK = FROM_BLOCK + 4999;
        let finished = false;
        while (!finished) {
            console.log(FROM_BLOCK, " to ", TO_BLOCK);

            var events1 = await contract1.getPastEvents("Borrow",{fromBlock: FROM_BLOCK,toBlock: TO_BLOCK,});
            for (var i = 0; i < events1.length; i++) {
                if(borrowersList.indexOf(events1[i].returnValues.to) === -1)
                {
                    borrowersList.push(events1[i].returnValues.to);
                }
            }
            events1 = await contract2.getPastEvents("Borrow",{fromBlock: FROM_BLOCK,toBlock: TO_BLOCK,});
            for (var i = 0; i < events1.length; i++) {
                if(borrowersList.indexOf(events1[i].returnValues.to) === -1)
                {
                    borrowersList.push(events1[i].returnValues.to);
                }
            }
            events1 = await contract3.getPastEvents("Borrow",{fromBlock: FROM_BLOCK,toBlock: TO_BLOCK,});
            for (var i = 0; i < events1.length; i++) {
                if(borrowersList.indexOf(events1[i].returnValues.to) === -1)
                {
                    borrowersList.push(events1[i].returnValues.to);
                }
            }

            /*
            var events1 = await contract1.getPastEvents(
                "LiquidateBorrow",
                {
                    fromBlock: FROM_BLOCK,
                    toBlock: TO_BLOCK,
                }
            );
            for (var i = 0; i < events1.length; i++) {
                console.log(events1[i].returnValues.to);
            }
            */




                //TODO parse events
                /*let to = events[i].returnValues.to;
                const timestamp = (await Web3_bsc.eth.getBlock(events[i].blockNumber)).timestamp;

                if(timestamp<endTimeStamp)
                {

                    let amount = (Number(events[i].returnValues.amount1In) + Number(events[i].returnValues.amount1Out)); // / 1000000000000000000;

                    //console.log(to,amount);
                    if (map.has(to)) {
                        map.set(to, map.get(to) + amount)
                    } else {
                        map.set(to, amount)
                        addresses.push(to);
                    }
                }
                else
                {
                    finished = true;
                    console.log("FINAL BLOCK: ", events[i].blockNumber)
                    break;
                }*/
                //console.log(to, " transferred ", map.get(to)); //JSON.stringify(events)

                //map.set(events[i].returnValues.to, map.get(events[i].returnValues.to)+(Number(events[i].returnValues.amount1In) + Number(events[i].returnValues.amount1Out)) / 1000000000000000000)
                //console.log(events[i].returnValues.to, " on ", timestamp, " transferred ", (Number(events[i].returnValues.amount1In) + Number(events[i].returnValues.amount1Out)) / 1000000000000000000); //JSON.stringify(events)
            if(TO_BLOCK>FINAL_BLOCK)
            {
                finished = true;
                console.log("FINAL BLOCK: ", TO_BLOCK)
                break;
            }
            //finished = true;
            FROM_BLOCK = TO_BLOCK+1;
            TO_BLOCK = FROM_BLOCK+4999;
        }
        //console.log(borrowers);

        return borrowersList;

        //console.log();
      //console.log(addresses.length);

        /*for (var i = 0; i < addresses.length; i++) {
            console.log(addresses[i],map.get(addresses[i]));
        }*/
      //0x903187aBA1c7DCC4d70a40aF7b6fBA16293E0001 1131.3995547021364 + 1222.6353305547666

    } catch (err) {
      console.error("____ ERR", err);
    }

}

main().then(() => {
  console.log("FINISHED !!!");
});

// https://bscscan.com/tx/0xcdceb49c13de0af901b73adacead01b8a877c00b44023459dbc6f8ce736c3a75

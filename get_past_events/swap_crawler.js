// const { web3 } = require("hardhat");
const Web3 = require("web3");
const abi = require("./abis/abi");
const abi2 = require("./abis/abi2");

const Web3_bsc = new Web3("https://bsc-dataseed1.binance.org:443");

const ADDRESS = "0x1dF0B759ee5b144852EEb571bbA9CCA2aec66b35";
const ADDRESS2 = "0x289D2C8D914e0a7EAf9991D0E848D4A8795f022d";
//const FROM_BLOCK = "18610000";
//const FROM_BLOCK = "14185612"; //"18610000";
//const TO_BLOCK = "14186112"; //"18615000";
//const TO_BLOCK = "14190612";//"18615000";
//const TO_BLOCK = "18615000";

const contract = new Web3_bsc.eth.Contract(abi, ADDRESS);
const contract2 = new Web3_bsc.eth.Contract(abi2, ADDRESS2);

//console.log(toTimestamp('01/07/2022 00:00:00'));
let map = new Map();
let addresses = [];
let amounts = [];

const startTimeStamp = toTimestamp('01/08/2022 00:00:00');
const endTimeStamp = startTimeStamp + 86400;
let FROM_BLOCK = 14170827; //"18610000";
let TO_BLOCK = FROM_BLOCK + 4999; //"18615000"; 28800

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

  await ScanData();


  /* aqui tienes un ejemplo de como llamar a otro contrato
  const resultadoFunction = await contract2.nombreFunction(param1, param2)*/
    console.log(addresses.length);

  for (var i = 0; i < addresses.length; i++) {
      console.log(addresses[i],",");
  }

  for (var i = 0; i < addresses.length; i++) {
      //console.log(eToNumber(map.get(addresses[i])),",");
      amounts.push((map.get(addresses[i])));
      /*let ten =new BigNumber(map.get(addresses[i]));
      console.log(ten.toString());*/
  }

    for (var i = 0; i < addresses.length; i++) {
        console.log(eToNumber(amounts[i]),",");
    }

  //await contract2.SwapRewardRegisterUser(0,addresses,amounts);
    //var account = Web3_bsc.eth.accounts[0];
  //console.log(account);
  //await contract2.methods.SwapRewardRegisterUsers(0,addresses,amounts).send({from:account});
}
async function ScanData() {
try {
    let finished = false;
    while (!finished) {
        console.log(FROM_BLOCK, " to ", TO_BLOCK);
        const events = await contract.getPastEvents(
            "Swap", // "allEvents",
            {
                fromBlock: FROM_BLOCK,
                toBlock: TO_BLOCK,
            }
        );

        for (var i = 0; i < events.length; i++) {
            let to = events[i].returnValues.to;
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
            }
            //console.log(to, " transferred ", map.get(to)); //JSON.stringify(events)

            //map.set(events[i].returnValues.to, map.get(events[i].returnValues.to)+(Number(events[i].returnValues.amount1In) + Number(events[i].returnValues.amount1Out)) / 1000000000000000000)
            //console.log(events[i].returnValues.to, " on ", timestamp, " transferred ", (Number(events[i].returnValues.amount1In) + Number(events[i].returnValues.amount1Out)) / 1000000000000000000); //JSON.stringify(events)
        }

        FROM_BLOCK = TO_BLOCK+1;
        TO_BLOCK = FROM_BLOCK+4999;
    }

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

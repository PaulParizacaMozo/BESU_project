const path = require("path");
const fs = require("fs");
const Web3 = require("web3");

const RPC_URL = "http://localhost:8545";
const PRIVATE_KEY = "0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63";

// Direcciones del deploy
const ADDR_USER_VERIFICATION = "0x42699A7612A82f1d9C36148af9C77354759b210b";
const ADDR_VERTIPORT_MGMT = "0xa50a51c09a5c451C52BB714527E1974b686D8e77";
const ADDR_EVTOL_MGMT = "0x9a3DBCa554e9f6b9257aAa24010DA8377C57c17e";
const ADDR_FLIGHT_RESERVATION = "0x9B8397f1B0FEcD3a1a40CdD5E8221Fa461898517";

// IDs únicos
const SUFFIX = Date.now().toString();
const V_ORIG_ID = "V_ORIG_" + SUFFIX;
const V_DEST_ID = "V_DEST_" + SUFFIX;
const TRIP_ID = "TRIP_" + SUFFIX;
const EVTOL_ID = parseInt(SUFFIX.slice(-6), 10);  // número variable pero válido

function loadContract(name, address, web3) {
  const jsonPath = path.resolve(__dirname, "../contracts", `${name}.json`);
  const json = JSON.parse(fs.readFileSync(jsonPath, "utf8"));
  return new web3.eth.Contract(json.abi, address);
}

async function main() {
  const web3 = new Web3(RPC_URL);
  const account = web3.eth.accounts.privateKeyToAccount(PRIVATE_KEY);
  web3.eth.accounts.wallet.add(account);
  web3.eth.defaultAccount = account.address;

  console.log("Using account:", account.address);
  console.log("IDs usados en este smoke FULL:");
  console.log("  V_ORIG_ID:", V_ORIG_ID);
  console.log("  V_DEST_ID:", V_DEST_ID);
  console.log("  TRIP_ID  :", TRIP_ID);
  console.log("  EVTOL_ID :", EVTOL_ID);

  const userVerification = loadContract(
    "UserVerification",
    ADDR_USER_VERIFICATION,
    web3
  );
  const vertiportMgmt = loadContract(
    "VertiportManagement",
    ADDR_VERTIPORT_MGMT,
    web3
  );
  const evtolMgmt = loadContract("EVTOLManagement", ADDR_EVTOL_MGMT, web3);
  const flightReservation = loadContract(
    "FlightReservation",
    ADDR_FLIGHT_RESERVATION,
    web3
  );

  // ---------- 1) Autorizar usuario ----------
  const rider = account.address;
  console.log("\n[1] Setting canRide = true for rider:", rider);

  await userVerification.methods
    .setRiderPermission(rider, true)
    .send({ from: account.address, gas: 200000 });

  const canRide = await userVerification.methods
    .canUserRide(rider)
    .call();
  console.log("    canUserRide(rider):", canRide);

  // ---------- 2) Registrar vertiports ----------
  const portCred = "0x01";
  console.log("\n[2] Registering vertiports", V_ORIG_ID, "and", V_DEST_ID);

  await vertiportMgmt.methods
    .registerVertiport(V_ORIG_ID, 1, 1, portCred)
    .send({ from: account.address, gas: 300000 });
  console.log("    V_ORIG registrado");

  await vertiportMgmt.methods
    .registerVertiport(V_DEST_ID, 1, 1, portCred)
    .send({ from: account.address, gas: 300000 });
  console.log("    V_DEST registrado");

  // ---------- 3) Registrar EVTOL ----------
  const evtolCred = "0x02";
  console.log(`\n[3] Registering EVTOL id = ${EVTOL_ID} at ${V_ORIG_ID}`);

  await evtolMgmt.methods
    .registerEVTOL(EVTOL_ID, V_ORIG_ID, evtolCred)
    .send({ from: account.address, gas: 300000 });

  const isAvailable = await evtolMgmt.methods.isAvailable(EVTOL_ID).call();
  console.log("    EVTOL isAvailable:", isAvailable);

  // ---------- 4) Crear reserva ----------
  console.log("\n[4] Creating reservation", TRIP_ID);

  await flightReservation.methods
    .createReservation(
      TRIP_ID,
      rider,
      V_ORIG_ID,
      V_DEST_ID,
      EVTOL_ID,
      "0x03", // userCredential mock
      portCred,
      evtolCred
    )
    .send({ from: account.address, gas: 500000 });

  let trip = await flightReservation.methods.getTrip(TRIP_ID).call();
  console.log("    Trip after createReservation:");
  console.log("      id         :", trip.id);
  console.log("      status     :", trip.status.toString(), "(1 = CONFIRMED)");

  // ---------- 5) Ajuste de capacidad en ORIGEN (manual) ----------
  console.log("\n[5] Ajustando capacidad en origen antes de startTrip");
  let originState = await vertiportMgmt.methods
    .getVertiportState(V_ORIG_ID)
    .call();
  console.log("    Antes ajuste - origin n_parkings_free:",
    originState.n_parkings_free.toString()
  );

  // Ocupamos 1 parking en origen (free: 1 -> 0)
  await vertiportMgmt.methods
    .updateVertiportState(V_ORIG_ID, portCred, 0, -1)
    .send({ from: account.address, gas: 300000 });

  originState = await vertiportMgmt.methods
    .getVertiportState(V_ORIG_ID)
    .call();
  console.log("    Despues ajuste - origin n_parkings_free:",
    originState.n_parkings_free.toString()
  );

  // ---------- 6) startTrip ----------
  console.log("\n[6] Calling startTrip", TRIP_ID);
  await flightReservation.methods
    .startTrip(TRIP_ID, portCred)
    .send({ from: account.address, gas: 400000 });

  trip = await flightReservation.methods.getTrip(TRIP_ID).call();
  console.log("    Trip after startTrip:");
  console.log("      status     :", trip.status.toString(), "(2 = IN_PROGRESS)");

  originState = await vertiportMgmt.methods
    .getVertiportState(V_ORIG_ID)
    .call();
  console.log("    Origin n_parkings_free after startTrip:",
    originState.n_parkings_free.toString()
  );

  // ---------- 7) completeTrip ----------
  console.log("\n[7] Calling completeTrip", TRIP_ID);
  await flightReservation.methods
    .completeTrip(TRIP_ID, portCred)  // usamos misma cred mock para destino
    .send({ from: account.address, gas: 400000 });

  trip = await flightReservation.methods.getTrip(TRIP_ID).call();
  console.log("    Trip after completeTrip:");
  console.log("      status     :", trip.status.toString(), "(3 = COMPLETED)");

  const destState = await vertiportMgmt.methods
    .getVertiportState(V_DEST_ID)
    .call();
  console.log("    Dest n_parkings_free after completeTrip:",
    destState.n_parkings_free.toString()
  );

  console.log("\nSmoke test FULL finished OK.");
}

main().catch((err) => {
  console.error("Error in FULL smoke test:", err);
  process.exit(1);
});


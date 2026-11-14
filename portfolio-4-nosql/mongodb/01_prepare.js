// =====================================================================
// MIT 8103 - Portfolio 4: prepare the MongoDB collections after mongoimport
// Run: mongosh laguna_care mongodb/01_prepare.js
// 1. converts ISO date strings into real BSON dates
// 2. adds $jsonSchema validators (schema-on-write for the fields that matter)
// =====================================================================
db = db.getSiblingDB("laguna_care");

print("== 1. Convert ISO date strings to BSON dates ==");
let r = db.patients.updateMany({}, [
  { $set: { dateOfBirth: { $toDate: "$dateOfBirth" }, registeredAt: { $toDate: "$registeredAt" } } }
]);
print(`patients updated:   ${r.modifiedCount}`);

r = db.encounters.updateMany({}, [
  { $set: {
      startedAt: { $toDate: "$startedAt" },
      labResults: {
        $cond: [
          { $isArray: "$labResults" },
          { $map: {
              input: "$labResults", as: "l",
              in: { $cond: [
                { $ifNull: ["$$l.resultAt", false] },
                { $mergeObjects: ["$$l", { resultAt: { $toDate: "$$l.resultAt" } }] },
                "$$l"
              ] }
          } },
          "$$REMOVE"
        ]
      }
  } }
]);
print(`encounters updated: ${r.modifiedCount}`);

print("\n== 2. Add JSON Schema validators ==");
db.runCommand({
  collMod: "patients",
  validationLevel: "strict",
  validationAction: "error",
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["_id", "name", "dateOfBirth", "sex", "homeBranch", "contact"],
    properties: {
      _id:         { bsonType: "string", pattern: "^LCH-[0-9]{7}$" },
      name:        { bsonType: "object", required: ["first", "last"],
                     properties: { first: { bsonType: "string" }, last: { bsonType: "string" } } },
      dateOfBirth: { bsonType: "date" },
      sex:         { enum: ["M", "F"] },
      bloodGroup:  { enum: ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"] },
      homeBranch:  { enum: ["IKJ", "LKI", "YAB"] },
      allergies:   { bsonType: "array", items: { bsonType: "string" } },
      insurance:   { bsonType: "object", required: ["provider", "policyNo"] }
    }
  } }
});
db.runCommand({
  collMod: "encounters",
  validationLevel: "strict",
  validationAction: "error",
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["_id", "patientId", "branch", "type", "startedAt", "doctor"],
    properties: {
      patientId:  { bsonType: "string" },
      branch:     { enum: ["IKJ", "LKI", "YAB"] },
      type:       { enum: ["outpatient", "emergency", "inpatient", "follow_up"] },
      startedAt:  { bsonType: "date" },
      doctor:     { bsonType: "object", required: ["staffId", "name"] },
      diagnoses:  { bsonType: "array",
                    items: { bsonType: "object", required: ["code", "primary"] } },
      labResults: { bsonType: "array",
                    items: { bsonType: "object", required: ["test", "status"] } }
    }
  } }
});
print("validators added to patients and encounters");

print("\n== Collection sizes ==");
print(`patients:   ${db.patients.countDocuments()}`);
print(`encounters: ${db.encounters.countDocuments()}`);
printjson(db.encounters.findOne({ type: "emergency", labResults: { $exists: true } }));

// =====================================================================
// MIT 8103 - Portfolio 4: MongoDB queries on the hospital document model
// Run: mongosh laguna_care mongodb/02_queries.js > results/mongodb_output.txt
// Each query is shown WITHOUT and then WITH a supporting index, using
// explain("executionStats"), followed by its result.
// =====================================================================
db = db.getSiblingDB("laguna_care");

// --- helpers --------------------------------------------------------
function plan(exp) {
  const stages = [];
  (function walk(p) {
    if (!p) return;
    stages.push(p.stage + (p.indexName ? `(${p.indexName})` : ""));
    walk(p.inputStage);
    (p.inputStages || []).forEach(walk);
  })(exp.queryPlanner.winningPlan.queryPlan || exp.queryPlanner.winningPlan);
  const s = exp.executionStats;
  return `${stages.join(" <- ")}\n      docsExamined=${s.totalDocsExamined}  keysExamined=${s.totalKeysExamined}` +
         `  returned=${s.nReturned}  time=${s.executionTimeMillis} ms`;
}
function title(t) { print("\n" + "=".repeat(76) + "\n" + t + "\n" + "=".repeat(76)); }

// start from a clean set of indexes so the before/after comparison is fair
db.patients.dropIndexes();
db.encounters.dropIndexes();

// --------------------------------------------------------------------
title("M1. Patient history: all visits of LCH-0000013, newest first (ONE query, no joins)");
const m1 = () => db.encounters.find(
  { patientId: "LCH-0000013" },
  { startedAt: 1, branch: 1, "doctor.name": 1, complaint: 1, diagnoses: 1, "prescriptions.drug": 1, "labResults.test": 1 }
).sort({ startedAt: -1 });
print("  before index: " + plan(m1().explain("executionStats")));
db.encounters.createIndex({ patientId: 1, startedAt: -1 }, { name: "patient_history" });
print("  after index:  " + plan(m1().explain("executionStats")));
m1().forEach(d => print(`  ${d.startedAt.toISOString().slice(0, 10)} ${d.branch} ${d.doctor.name.padEnd(24)} ` +
  `${(d.diagnoses || []).filter(x => x.primary).map(x => x.code + " " + x.description).join("")}` +
  ` | drugs: ${(d.prescriptions || []).map(p => p.drug).join(", ") || "-"}` +
  ` | labs: ${(d.labResults || []).map(l => l.test).join(", ") || "-"}`));

// --------------------------------------------------------------------
title("M2. Front-desk search: surname OKAFOR, first name chinedu (case-insensitive)");
const ci = { locale: "en", strength: 2 };   // strength 2 = ignore case
const m2 = () => db.patients.find({ "name.last": "OKAFOR", "name.first": "chinedu" },
                                  { name: 1, dateOfBirth: 1, "contact.phone": 1 }).collation(ci);
print("  before index: " + plan(m2().explain("executionStats")));
db.patients.createIndex({ "name.last": 1, "name.first": 1 }, { name: "name_ci", collation: ci });
print("  after index:  " + plan(m2().explain("executionStats")));
m2().forEach(d => print(`  ${d._id}  ${d.name.first} ${d.name.last}  born ${d.dateOfBirth.toISOString().slice(0, 10)}`));

// --------------------------------------------------------------------
title("M3. Clinical alert: FBC results with haemoglobin below 8 g/dL (field exists only in FBC results)");
const m3filter = { labResults: { $elemMatch: { test: "FBC", "values.hb_g_dL": { $lt: 8 } } } };
const m3 = () => db.encounters.find(m3filter, { patientId: 1, startedAt: 1, branch: 1, "labResults.$": 1 })
                              .sort({ startedAt: -1 }).limit(5);
print("  before index: " + plan(m3().explain("executionStats")));
db.encounters.createIndex({ "labResults.test": 1, "labResults.values.hb_g_dL": 1 }, { name: "lab_test_hb" });
print("  after index:  " + plan(m3().explain("executionStats")));
print(`  matching encounters: ${db.encounters.countDocuments(m3filter)} (latest 5 below)`);
m3().forEach(d => print(`  ${d.patientId} ${d.startedAt.toISOString().slice(0, 10)} ${d.branch}  Hb=${d.labResults[0].values.hb_g_dL}`));

// --------------------------------------------------------------------
title("M4. Aggregation: top 3 primary diagnoses per branch in 2025");
db.encounters.aggregate([
  { $match: { startedAt: { $gte: ISODate("2025-01-01"), $lt: ISODate("2026-01-01") } } },
  { $unwind: "$diagnoses" },
  { $match: { "diagnoses.primary": true } },
  { $group: { _id: { branch: "$branch", code: "$diagnoses.code", description: "$diagnoses.description" },
              visits: { $sum: 1 } } },
  { $sort: { "_id.branch": 1, visits: -1 } },
  { $group: { _id: "$_id.branch",
              top: { $push: { code: "$_id.code", description: "$_id.description", visits: "$visits" } } } },
  { $project: { _id: 0, branch: "$_id", top3: { $slice: ["$top", 3] } } },
  { $sort: { branch: 1 } }
]).forEach(b => print(`  ${b.branch}: ` + b.top3.map(t => `${t.code} ${t.description} (${t.visits})`).join("; ")));

// --------------------------------------------------------------------
title("M5. Safety check ($lookup): patients allergic to Penicillin who were prescribed Amoxicillin");
db.encounters.createIndex({ "prescriptions.drug": 1 }, { name: "prescribed_drug" });
const m5 = db.patients.aggregate([
  { $match: { allergies: "Penicillin" } },
  { $lookup: { from: "encounters", localField: "_id", foreignField: "patientId",
               pipeline: [ { $match: { "prescriptions.drug": "Amoxicillin" } },
                           { $project: { _id: 1, startedAt: 1, branch: 1 } } ],
               as: "amoxicillinVisits" } },
  { $match: { "amoxicillinVisits.0": { $exists: true } } },
  { $project: { name: { $concat: ["$name.first", " ", "$name.last"] }, visits: { $size: "$amoxicillinVisits" } } },
  { $sort: { visits: -1, _id: 1 } }
]).toArray();
print(`  patients at risk: ${m5.length} (first 5 below)`);
m5.slice(0, 5).forEach(p => print(`  ${p._id}  ${p.name.padEnd(22)} amoxicillin prescribed in ${p.visits} visit(s)`));

// --------------------------------------------------------------------
title("M6. Flexible schema: vital-sign fields differ between documents");
print(`  encounters with GCS recorded (emergency only): ${db.encounters.countDocuments({ "vitals.gcs": { $exists: true } })}`);
print(`  encounters without GCS:                        ${db.encounters.countDocuments({ "vitals.gcs": { $exists: false } })}`);
print(`  distinct lab tests stored with their own value fields: ${db.encounters.distinct("labResults.test").length}`);

// --------------------------------------------------------------------
title("M7. Updates: add a new lab result to a visit, and a new field to a patient");
const enc = db.encounters.findOne({ patientId: "LCH-0000013" }, { _id: 1 }, { sort: { startedAt: -1 } });
let u = db.encounters.updateOne({ _id: enc._id }, { $push: { labResults: {
  test: "MP", name: "Malaria Parasite", priority: "urgent", status: "completed",
  resultAt: new Date(), abnormal: true,
  values: { result: "positive", species: "P. falciparum", parasitesPerUL: 12000 } } } });
print(`  $push lab result into ${enc._id}: modified=${u.modifiedCount}`);
u = db.patients.updateOne({ _id: "LCH-0000013" },
  { $set: { emergencyContact: { name: "Mr Akinola", relationship: "spouse", phone: "08099999999" } } });
print(`  $set new field emergencyContact (no ALTER TABLE needed): modified=${u.modifiedCount}`);
// undo, so the script can be run again with the same results
db.encounters.updateOne({ _id: enc._id }, { $pop: { labResults: 1 } });
db.patients.updateOne({ _id: "LCH-0000013" }, { $unset: { emergencyContact: "" } });

// --------------------------------------------------------------------
title("M8. Schema validation rejects bad documents");
try {
  db.patients.insertOne({ _id: "LCH-9999999", name: { first: "Test", last: "Patient" },
    dateOfBirth: new Date("2000-01-01"), sex: "X", homeBranch: "IKJ", contact: { phone: "080" } });
  print("  inserted (validation NOT working)");
} catch (e) {
  print(`  REJECTED as expected: ${e.errInfo ? "Document failed validation (sex must be M or F)" : e.message}`);
}
try {
  db.encounters.insertOne({ _id: "ENC-X", patientId: "LCH-0000013", branch: "ABJ", type: "outpatient",
    startedAt: new Date(), doctor: { staffId: 1, name: "Dr Test" } });
  print("  inserted (validation NOT working)");
} catch (e) {
  print(`  REJECTED as expected: ${e.errInfo ? "Document failed validation (branch ABJ does not exist)" : e.message}`);
}

title("Indexes created");
db.encounters.getIndexes().forEach(i => print(`  encounters: ${i.name}  ${JSON.stringify(i.key)}`));
db.patients.getIndexes().forEach(i => print(`  patients:   ${i.name}  ${JSON.stringify(i.key)}`));

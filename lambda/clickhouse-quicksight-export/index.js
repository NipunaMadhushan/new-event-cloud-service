const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");

const s3 = new S3Client({});

const CLICKHOUSE_HOST = process.env.CLICKHOUSE_HOST; // e.g. http://clickhouse.data.svc.cluster.local:8123
const CLICKHOUSE_USER = process.env.CLICKHOUSE_USER || "default";
const CLICKHOUSE_PASSWORD = process.env.CLICKHOUSE_PASSWORD;
const S3_BUCKET = process.env.S3_BUCKET;

// Daily rollup, not a raw dump — re-running this within the same day just
// overwrites that day's partition with an up-to-date count, so the 15-minute
// schedule is safe to re-run/retry without producing duplicate rows in Athena.
// count() returns UInt64, which ClickHouse's JSONEachRow format always quotes
// as a JSON string (output_format_json_quote_64bit_integers) to avoid
// precision loss in JS-based JSON parsers. That silently turned event_count
// into a STRING column all the way through Glue/Athena/QuickSight, so every
// QuickSight visual defaulted to counting rows instead of summing the real
// value — every chart showed uniform small numbers with no relation to
// actual event volume. Casting down to a 32-bit int avoids the quoting.
const QUERY = `
  SELECT
    toDate(event_timestamp) AS event_date,
    event_type,
    page,
    toInt32(count()) AS event_count
  FROM web_events
  WHERE event_timestamp >= now() - INTERVAL 1 DAY
  GROUP BY event_date, event_type, page
  ORDER BY event_date, event_type, page
  FORMAT JSONEachRow
`;

exports.handler = async () => {
  const url = `${CLICKHOUSE_HOST}/?query=${encodeURIComponent(QUERY)}`;
  const auth = Buffer.from(`${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}`).toString("base64");

  const res = await fetch(url, {
    headers: { Authorization: `Basic ${auth}` }
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`ClickHouse query failed (${res.status}): ${errText}`);
  }

  const body = await res.text();
  const today = new Date().toISOString().slice(0, 10);
  // Fixed key per day (not per invocation) so the rollup is overwritten, not duplicated.
  const key = `web_events_rollup/date=${today}/rollup.json`;

  await s3.send(new PutObjectCommand({
    Bucket: S3_BUCKET,
    Key: key,
    Body: body,
    ContentType: "application/json"
  }));

  console.log(`Exported rollup to s3://${S3_BUCKET}/${key}`);
  return { statusCode: 200 };
};

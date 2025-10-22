import { CreateTableCommand, DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { fromIni } from "@aws-sdk/credential-provider-ini";
import {
  DeleteCommand,
  DynamoDBDocumentClient,
  PutCommand,
  QueryCommand,
  ScanCommand,
} from "@aws-sdk/lib-dynamodb";

const TABLE_NAME = "download-queue";

const client = new DynamoDBClient({
  region: "us-west-2",
  credentials: fromIni({ profile: "personal" }),
});

const docClient = DynamoDBDocumentClient.from(client);

export interface DownloadItem {
  id: string;
  creationTime: string;
  url: string;
  filename: string;
  error?: string;
  lastAttempt?: string;
}

export async function createTable() {
  try {
    await client.send(
      new CreateTableCommand({
        TableName: TABLE_NAME,
        AttributeDefinitions: [
          {
            AttributeName: "id",
            AttributeType: "S",
          },
          {
            AttributeName: "creationTime",
            AttributeType: "S",
          },
        ],
        KeySchema: [
          {
            AttributeName: "id",
            KeyType: "HASH",
          },
          {
            AttributeName: "creationTime",
            KeyType: "RANGE",
          },
        ],
        BillingMode: "PAY_PER_REQUEST",
      }),
    );
    console.log(`Table ${TABLE_NAME} created successfully`);
  } catch (error) {
    if (error instanceof Error && error.name === "ResourceInUseException") {
      console.log(`Table ${TABLE_NAME} already exists`);
    } else {
      throw error;
    }
  }
}

export async function addDownloadItem(
  url: string,
  linkText: string,
): Promise<DownloadItem> {
  const filename = generateFilename(linkText);
  const item: DownloadItem = {
    id: generateId(),
    creationTime: new Date().toISOString(),
    url,
    filename,
  };

  await docClient.send(
    new PutCommand({
      TableName: TABLE_NAME,
      Item: item,
    }),
  );

  return item;
}

export async function listDownloadItems(
  errorsOnly = false,
): Promise<DownloadItem[]> {
  const result = await docClient.send(
    new ScanCommand({
      TableName: TABLE_NAME,
    }),
  );

  const items = (result.Items as DownloadItem[]) || [];

  // Sort by creationTime
  items.sort((a, b) => a.creationTime.localeCompare(b.creationTime));

  if (errorsOnly) {
    return items.filter((item) => item.error);
  }

  return items;
}

export async function removeById(id: string): Promise<void> {
  const items = await listDownloadItems();
  const item = items.find((i) => i.id === id);

  if (!item) {
    throw new Error(`No item found with id: ${id}`);
  }

  await docClient.send(
    new DeleteCommand({
      TableName: TABLE_NAME,
      Key: {
        id: item.id,
        creationTime: item.creationTime,
      },
    }),
  );
}

export async function removeByUrl(url: string): Promise<void> {
  const items = await listDownloadItems();
  const item = items.find((i) => i.url === url);

  if (!item) {
    throw new Error(`No item found with url: ${url}`);
  }

  await docClient.send(
    new DeleteCommand({
      TableName: TABLE_NAME,
      Key: {
        id: item.id,
        creationTime: item.creationTime,
      },
    }),
  );
}

function generateId(): string {
  return Math.random().toString(36).substring(2, 15);
}

export function generateFilename(text: string): string {
  // Replace non-alphanumeric characters with dashes and convert to lowercase
  const sanitized = text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, ""); // Remove leading/trailing dashes

  return `${sanitized || "download"}.zip`;
}

export async function updateItemError(
  id: string,
  error: string,
): Promise<void> {
  const items = await listDownloadItems();
  const item = items.find((i) => i.id === id);

  if (!item) {
    throw new Error(`No item found with id: ${id}`);
  }

  await docClient.send(
    new PutCommand({
      TableName: TABLE_NAME,
      Item: {
        ...item,
        error,
        lastAttempt: new Date().toISOString(),
      },
    }),
  );
}

export async function getById(id: string): Promise<DownloadItem | undefined> {
  const result = await docClient.send(
    new QueryCommand({
      TableName: TABLE_NAME,
      KeyConditionExpression: "id = :id",
      ExpressionAttributeValues: {
        ":id": id,
      },
    }),
  );

  const items = result.Items as DownloadItem[];
  return items?.[0];
}

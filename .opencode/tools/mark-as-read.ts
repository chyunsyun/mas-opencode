import { tool } from "@opencode-ai/plugin";
import { existsSync } from "node:fs";
import {
  mkdir,
  readFile,
  rename,
  rm,
  rmdir,
  writeFile,
} from "node:fs/promises";
import path from "node:path";

const LOCK_RETRY_COUNT = 50;
const LOCK_RETRY_DELAY_MS = 100;

// Dedicated inbox state updater.
// It only flips a processed inbox entry from read:false to read:true.

const AGENT_ID_RE = /^[a-z][a-z0-9_-]*$/;

type InboxBlock = {
  id?: string;
  idLine?: number;
  read?: "true" | "false";
  readLine?: number;
};

function stripYamlScalarQuotes(value: string): string {
  if (
    (value.startsWith("'") && value.endsWith("'")) ||
    (value.startsWith('"') && value.endsWith('"'))
  ) {
    return value.slice(1, -1);
  }
  return value;
}

function resolveInboxPath(projectRoot: string, agentId: string): string {
  const normalizedAgentId = agentId.trim();
  if (!AGENT_ID_RE.test(normalizedAgentId)) {
    throw new Error(
      `Invalid agentId ${JSON.stringify(agentId)}. Expected a simple inbox name such as chief or engineer3.`,
    );
  }

  const inboxRoot = path.resolve(projectRoot, "queue", "inbox");
  const inboxPath = path.resolve(inboxRoot, `${normalizedAgentId}.yaml`);
  const relativeToInboxRoot = path.relative(inboxRoot, inboxPath);

  if (
    relativeToInboxRoot.startsWith("..") ||
    path.isAbsolute(relativeToInboxRoot)
  ) {
    throw new Error(
      `Refusing to access path outside queue/inbox: ${inboxPath}`,
    );
  }

  return inboxPath;
}

function parseInbox(raw: string): {
  lines: string[];
  newline: string;
  blocks: InboxBlock[];
} {
  const newline = raw.includes("\r\n") ? "\r\n" : "\n";
  const lines = raw.split(/\r?\n/);

  const headerIndex = lines.findIndex((line) => {
    const trimmed = line.trim();
    return trimmed.length > 0 && trimmed !== "---" && !trimmed.startsWith("#");
  });
  if (
    headerIndex === -1 ||
    !lines[headerIndex].trim().startsWith("messages:")
  ) {
    throw new Error("Inbox YAML must start with a top-level 'messages:' key.");
  }

  const blocks: InboxBlock[] = [];
  let currentBlock: InboxBlock | null = null;

  for (let i = headerIndex + 1; i < lines.length; i += 1) {
    const line = lines[i];

    if (line.startsWith("- ")) {
      if (currentBlock) {
        blocks.push(currentBlock);
      }
      currentBlock = {};
      const rest = line.slice(2);
      const inlineIdMatch = rest.match(/^id:\s*(.+)$/);
      if (inlineIdMatch) {
        currentBlock.id = stripYamlScalarQuotes(inlineIdMatch[1].trim());
        currentBlock.idLine = i;
      }
      continue;
    }

    if (!currentBlock) {
      continue;
    }

    const idMatch = line.match(/^  id:\s*(.+)$/);
    if (idMatch) {
      if (currentBlock.id !== undefined) {
        throw new Error(
          "Inbox YAML contains a duplicate id field within one message block.",
        );
      }
      currentBlock.id = stripYamlScalarQuotes(idMatch[1].trim());
      currentBlock.idLine = i;
      continue;
    }

    const readMatch = line.match(/^  read:\s*(true|false)\s*$/);
    if (readMatch) {
      if (currentBlock.read !== undefined) {
        throw new Error(
          "Inbox YAML contains a duplicate read field within one message block.",
        );
      }
      currentBlock.read = readMatch[1] as "true" | "false";
      currentBlock.readLine = i;
    }
  }

  if (currentBlock) {
    blocks.push(currentBlock);
  }

  return { lines, newline, blocks };
}

async function atomicWrite(filePath: string, contents: string): Promise<void> {
  const tempPath = `${filePath}.${process.pid}.${Date.now()}.tmp`;

  try {
    await writeFile(tempPath, contents, "utf8");
    await rename(tempPath, filePath);
  } finally {
    await rm(tempPath, { force: true }).catch(() => {});
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

async function withInboxLock<T>(
  inboxPath: string,
  operation: () => Promise<T>,
): Promise<T> {
  const lockDir = `${inboxPath}.lock.d`;

  for (let attempt = 0; attempt < LOCK_RETRY_COUNT; attempt += 1) {
    try {
      await mkdir(lockDir);
    } catch (error) {
      const code = (error as { code?: string }).code;
      if (code !== "EEXIST") {
        throw error;
      }
      await sleep(LOCK_RETRY_DELAY_MS);
      continue;
    }

    try {
      return await operation();
    } finally {
      await rmdir(lockDir).catch(() => {});
    }
  }

  throw new Error(
    `Failed to acquire inbox lock: ${path.relative(process.cwd(), lockDir)}`,
  );
}

function assertCurrentAgent(targetAgentId: string): void {
  const currentAgentId = process.env.OPENCODE_AGENT_ID?.trim();
  if (!currentAgentId) {
    throw new Error(
      "OPENCODE_AGENT_ID is required so mark-as-read can only update the current agent's inbox.",
    );
  }
  if (currentAgentId !== targetAgentId) {
    throw new Error(
      `Refusing to mark another agent's inbox as read: current=${currentAgentId}, target=${targetAgentId}.`,
    );
  }
}

async function markAsRead(
  projectRoot: string,
  agentId: string,
  messageId: string,
): Promise<{
  inboxPath: string;
  relativeInboxPath: string;
  changed: boolean;
}> {
  const normalizedMessageId = messageId.trim();
  if (!normalizedMessageId) {
    throw new Error("messageId must not be empty.");
  }

  const normalizedAgentId = agentId.trim();
  assertCurrentAgent(normalizedAgentId);

  const inboxPath = resolveInboxPath(projectRoot, normalizedAgentId);
  return withInboxLock(inboxPath, async () => {
    const raw = await readFile(inboxPath, "utf8");
    const { lines, newline, blocks } = parseInbox(raw);

    const targetBlocks = blocks.filter(
      (block) => block.id === normalizedMessageId,
    );
    if (targetBlocks.length === 0) {
      throw new Error(
        `Message ${JSON.stringify(normalizedMessageId)} was not found in ${path.relative(projectRoot, inboxPath)}.`,
      );
    }
    if (targetBlocks.length > 1) {
      throw new Error(
        `Inbox YAML contains duplicate message id ${JSON.stringify(normalizedMessageId)}.`,
      );
    }

    const targetBlock = targetBlocks[0];
    if (targetBlock.read === undefined) {
      throw new Error(
        `Message ${JSON.stringify(normalizedMessageId)} in ${path.relative(projectRoot, inboxPath)} has no read field.`,
      );
    }

    if (targetBlock.read === "true") {
      return {
        inboxPath,
        relativeInboxPath: path
          .relative(projectRoot, inboxPath)
          .split(path.sep)
          .join("/"),
        changed: false,
      };
    }

    if (targetBlock.readLine === undefined) {
      throw new Error(
        `Message ${JSON.stringify(normalizedMessageId)} in ${path.relative(projectRoot, inboxPath)} has no read line.`,
      );
    }

    lines[targetBlock.readLine] = "  read: true";
    const updated = lines.join(newline);
    await atomicWrite(
      inboxPath,
      updated.endsWith(newline) ? updated : `${updated}${newline}`,
    );

    return {
      inboxPath,
      relativeInboxPath: path
        .relative(projectRoot, inboxPath)
        .split(path.sep)
        .join("/"),
      changed: true,
    };
  });
}

export default tool({
  description:
    "Mark one processed inbox entry as read without using the generic Edit tool",
  args: {
    agentId: tool.schema
      .string()
      .trim()
      .regex(
        AGENT_ID_RE,
        "Agent IDs must match an inbox file name such as chief or engineer3",
      )
      .describe("Target inbox owner"),
    messageId: tool.schema
      .string()
      .trim()
      .min(1)
      .describe("Inbox message id to mark as read"),
  },
  async execute(args, context) {
    const masRoot = process.env.MAS_ROOT?.trim();
    const projectRoot = masRoot && masRoot !== "/" ? masRoot : context.directory;

    if (!projectRoot || projectRoot === "/") {
      throw new Error(
        "mark-as-read requires MAS_ROOT or a project directory so it can edit queue/inbox under the project root.",
      );
    }

    const inboxRoot = path.join(projectRoot, "queue", "inbox");
    if (!existsSync(inboxRoot)) {
      throw new Error(
        `mark-as-read could not find queue/inbox under ${projectRoot}. Set MAS_ROOT to the project root.`,
      );
    }

    const result = await markAsRead(
      projectRoot,
      args.agentId,
      args.messageId,
    );
    return result.changed
      ? `Marked ${result.relativeInboxPath} message ${args.messageId} as read.`
      : `Message ${args.messageId} in ${result.relativeInboxPath} was already read.`;
  },
});

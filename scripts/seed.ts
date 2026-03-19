import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcrypt';

const prisma = new PrismaClient();

const DEFAULT_AI_PROMPT = `You are a senior penetration tester reviewing automated enumeration results.

Target: {{target_ip}}
Domain: {{domain}}
Scan Date: {{scan_date}}

## Enumeration Output
{{run_output}}

## CVE Data
{{cve_data}}

Provide a security assessment with:
1. Executive Summary (2-3 sentences)
2. Critical Findings (severity: critical/high/medium/low/info)
3. Attack Vectors identified
4. Recommended Remediation Steps
5. Overall Risk Rating

Format findings as structured JSON in a \`severity_summary\` code block.`;

async function main() {
  // Seed admin user
  const existingAdmin = await prisma.user.findUnique({
    where: { username: 'admin' },
  });

  if (!existingAdmin) {
    const passwordHash = await bcrypt.hash('TestifyThusly99@', 10);
    await prisma.user.create({
      data: {
        username: 'admin',
        passwordHash,
        role: 'admin',
        mustResetPassword: true,
      },
    });
    console.log('Created admin user (must reset password on first login)');
  } else {
    console.log('Admin user already exists');
  }

  // Seed default settings
  const settings = [
    { key: 'ai_prompt_template', value: DEFAULT_AI_PROMPT },
  ];

  for (const setting of settings) {
    await prisma.setting.upsert({
      where: { key: setting.key },
      update: {},
      create: {
        key: setting.key,
        value: setting.value,
      },
    });
    console.log(`Setting "${setting.key}" ensured`);
  }

  // Mark stale running runs as failed (crash recovery)
  const staleCount = await prisma.run.updateMany({
    where: { status: 'running' },
    data: { status: 'failed' },
  });
  if (staleCount.count > 0) {
    console.log(`Marked ${staleCount.count} stale running runs as failed`);
  }
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());

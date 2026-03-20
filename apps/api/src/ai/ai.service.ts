import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CredentialsService } from '../credentials/credentials.service';
import { SettingsService } from '../settings/settings.service';
import { CveEnrichmentService } from './cve-enrichment.service';

const CVE_RE = /CVE-\d{4}-\d{4,}/g;

@Injectable()
export class AiService {
  private readonly logger = new Logger(AiService.name);

  constructor(
    private prisma: PrismaService,
    private credentials: CredentialsService,
    private settings: SettingsService,
    private cveEnrichment: CveEnrichmentService,
  ) {}

  async assess(runId: number, provider: 'claude' | 'openai') {
    const run = await this.prisma.run.findUnique({ where: { id: runId } });
    if (!run) throw new NotFoundException('Run not found');

    // Get API key
    const apiKey = await this.credentials.getDecryptedKey(provider);
    if (!apiKey) throw new NotFoundException(`No ${provider} API key configured`);

    // Get run outputs
    const outputs = await this.prisma.runOutput.findMany({
      where: { runId },
      orderBy: { id: 'asc' },
    });

    const runOutput = outputs
      .map((o) => `### ${o.commandName}\n${o.outputText}`)
      .join('\n\n');

    // Extract and enrich CVEs
    const cveIds = [...new Set(runOutput.match(CVE_RE) || [])];
    const cveData = cveIds.length > 0
      ? await this.cveEnrichment.enrichCves(cveIds)
      : [];

    const cveText = cveData.length > 0
      ? cveData.map((c) => `- ${c.id} (${c.severity}, score: ${c.score}): ${c.description}`).join('\n')
      : 'No CVEs identified in scan output.';

    // Build prompt from template
    const templateSetting = await this.settings.findByKey('ai_prompt_template');
    const prompt = templateSetting.value
      .replace('{{target_ip}}', run.targetIp)
      .replace('{{domain}}', run.domain || 'N/A')
      .replace('{{scan_date}}', run.startedAt?.toISOString() || 'Unknown')
      .replace('{{run_output}}', runOutput.slice(0, 50000))
      .replace('{{cve_data}}', cveText);

    // Call AI provider
    let response: string;
    if (provider === 'claude') {
      response = await this.callClaude(apiKey, prompt);
    } else {
      response = await this.callOpenAI(apiKey, prompt);
    }

    // Parse severity summary from response — try all code blocks, pick the one with severity counts
    let severitySummary = null;
    const codeBlocks = [...response.matchAll(/```(?:json)?\s*\n([\s\S]*?)\n```/g)];
    for (const match of codeBlocks) {
      try {
        const parsed = JSON.parse(match[1]);
        if (parsed && typeof parsed.critical === 'number') {
          severitySummary = parsed;
          break;
        }
        if (parsed?.severity_summary && typeof parsed.severity_summary.critical === 'number') {
          severitySummary = parsed.severity_summary;
          break;
        }
      } catch {
        // not valid JSON or not the severity block, try next
      }
    }
    if (!severitySummary) {
      this.logger.warn('No severity_summary JSON found in AI response');
    }

    // Save assessment
    const assessment = await this.prisma.aiAssessment.create({
      data: {
        runId,
        provider,
        promptUsed: prompt,
        response,
        severitySummary,
      },
    });

    return assessment;
  }

  async getAssessment(runId: number) {
    const assessment = await this.prisma.aiAssessment.findFirst({
      where: { runId },
      orderBy: { createdAt: 'desc' },
    });
    if (!assessment) throw new NotFoundException('No assessment found');
    return assessment;
  }

  private async callClaude(apiKey: string, prompt: string): Promise<string> {
    const Anthropic = (await import('@anthropic-ai/sdk')).default;
    const client = new Anthropic({ apiKey });

    const message = await client.messages.create({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 4096,
      messages: [{ role: 'user', content: prompt }],
    });

    return message.content
      .filter((block) => block.type === 'text')
      .map((block) => ('text' in block ? block.text : ''))
      .join('\n');
  }

  private async callOpenAI(apiKey: string, prompt: string): Promise<string> {
    const OpenAI = (await import('openai')).default;
    const client = new OpenAI({ apiKey });

    const completion = await client.chat.completions.create({
      model: 'gpt-4o',
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 4096,
    });

    return completion.choices[0]?.message?.content || '';
  }
}

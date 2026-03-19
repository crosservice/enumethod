import { Injectable } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { ConfigService } from '@nestjs/config';
import type { Request } from 'express';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(config: ConfigService) {
    super({
      jwtFromRequest: ExtractJwt.fromExtractors([
        // First try Authorization: Bearer header
        ExtractJwt.fromAuthHeaderAsBearerToken(),
        // Fall back to ?token= query parameter (for report/export URLs opened in browser)
        (req: Request) => req?.query?.token as string || null,
      ]),
      ignoreExpiration: false,
      secretOrKey: config.get('JWT_SECRET', 'dev-secret'),
    });
  }

  validate(payload: { sub: number; username: string; role: string; mustReset: boolean }) {
    return payload;
  }
}

import { Injectable, CanActivate, ExecutionContext, ForbiddenException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { IS_PUBLIC_KEY } from '../decorators/public.decorator';

const RESET_EXEMPT_PATHS = ['/api/auth/', '/api/users/change-password'];

@Injectable()
export class MustResetGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const request = context.switchToHttp().getRequest();
    const user = request.user;

    if (user?.mustReset) {
      const path = request.url;
      if (RESET_EXEMPT_PATHS.some((p) => path.startsWith(p))) return true;
      throw new ForbiddenException('Password reset required');
    }

    return true;
  }
}

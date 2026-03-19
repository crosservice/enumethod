import {
  WebSocketGateway,
  WebSocketServer,
  SubscribeMessage,
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { Logger } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';

@WebSocketGateway({
  namespace: '/ws/runs',
  cors: {
    origin: '*',
  },
})
export class RunsGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server: Server;

  private readonly logger = new Logger(RunsGateway.name);

  constructor(
    private jwt: JwtService,
    private config: ConfigService,
  ) {}

  async handleConnection(client: Socket) {
    try {
      const token = client.handshake.auth?.token;
      if (!token) {
        client.disconnect();
        return;
      }
      this.jwt.verify(token, {
        secret: this.config.get('JWT_SECRET', 'dev-secret'),
      });
      this.logger.debug(`Client connected: ${client.id}`);
    } catch {
      client.disconnect();
    }
  }

  handleDisconnect(client: Socket) {
    this.logger.debug(`Client disconnected: ${client.id}`);
  }

  @SubscribeMessage('subscribe')
  handleSubscribe(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { runId: number },
  ) {
    const room = `run:${data.runId}`;
    client.join(room);
    this.logger.debug(`Client ${client.id} subscribed to ${room}`);
  }

  emitOutput(runId: number, line: string, step: number, command: string | null) {
    this.server.to(`run:${runId}`).emit('output', { line, step, command });
  }

  emitStatus(runId: number, status: string, step: number) {
    this.server.to(`run:${runId}`).emit('status', { status, step });
  }

  emitCatchup(runId: number, clientId: string, data: { lines: string[]; step: number; command: string | null; status: string }) {
    this.server.to(clientId).emit('catchup', data);
  }
}

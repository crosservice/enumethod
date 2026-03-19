import { Controller, Get, Post, Delete, Body, Param, UseGuards } from '@nestjs/common';
import { CredentialsService } from './credentials.service';
import { CreateCredentialDto } from './dto/create-credential.dto';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ParseIntIdPipe } from '../common/pipes/parse-int-id.pipe';

@Controller('credentials')
@UseGuards(RolesGuard)
@Roles('admin')
export class CredentialsController {
  constructor(private credentials: CredentialsService) {}

  @Get()
  findAll() {
    return this.credentials.findAll();
  }

  @Post()
  create(@Body() dto: CreateCredentialDto, @CurrentUser('sub') userId: number) {
    return this.credentials.create(dto.name, dto.provider, dto.apiKey, userId);
  }

  @Delete(':id')
  remove(@Param('id', ParseIntIdPipe) id: number) {
    return this.credentials.delete(id);
  }
}

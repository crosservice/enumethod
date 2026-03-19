import { Controller, Get, Put, Param, Body, UseGuards } from '@nestjs/common';
import { SettingsService } from './settings.service';
import { UpdateSettingDto } from './dto/update-setting.dto';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';

@Controller('settings')
export class SettingsController {
  constructor(private settings: SettingsService) {}

  @Get()
  findAll() {
    return this.settings.findAll();
  }

  @Put(':key')
  @UseGuards(RolesGuard)
  @Roles('admin')
  update(
    @Param('key') key: string,
    @Body() dto: UpdateSettingDto,
    @CurrentUser('sub') userId: number,
  ) {
    return this.settings.update(key, dto.value, userId);
  }
}

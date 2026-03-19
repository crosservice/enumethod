import { Controller, Get, Post, Patch, Delete, Body, Param, UseGuards } from '@nestjs/common';
import { UsersService } from './users.service';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';
import { ChangePasswordDto } from './dto/change-password.dto';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ParseIntIdPipe } from '../common/pipes/parse-int-id.pipe';

@Controller('users')
export class UsersController {
  constructor(private users: UsersService) {}

  @Get()
  @UseGuards(RolesGuard)
  @Roles('admin')
  findAll() {
    return this.users.findAll();
  }

  @Post()
  @UseGuards(RolesGuard)
  @Roles('admin')
  create(@Body() dto: CreateUserDto) {
    return this.users.create(dto.username, dto.password, dto.role);
  }

  @Patch(':id')
  @UseGuards(RolesGuard)
  @Roles('admin')
  update(@Param('id', ParseIntIdPipe) id: number, @Body() dto: UpdateUserDto) {
    return this.users.update(id, dto);
  }

  @Delete(':id')
  @UseGuards(RolesGuard)
  @Roles('admin')
  remove(@Param('id', ParseIntIdPipe) id: number) {
    return this.users.delete(id);
  }

  @Post('change-password')
  changePassword(@CurrentUser('sub') userId: number, @Body() dto: ChangePasswordDto) {
    return this.users.changePassword(userId, dto.currentPassword, dto.newPassword);
  }
}

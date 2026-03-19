import { PipeTransform, Injectable, BadRequestException } from '@nestjs/common';

@Injectable()
export class ParseIntIdPipe implements PipeTransform {
  transform(value: string): number {
    const id = parseInt(value, 10);
    if (isNaN(id) || id < 1) {
      throw new BadRequestException('Invalid ID');
    }
    return id;
  }
}

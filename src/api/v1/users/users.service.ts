import {
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';

import { UsersRepository } from './users.repository';
import { UsersModel } from './users.model';
import { BaseService } from '../shared/base.service';
import * as bcrypt from 'bcrypt';

import { UserListDto } from './dto/user-list.dto';
import { CreateUserDto } from './dto/create-user.dto';
import { ResponseUserDto } from '../auth/interfaces/user.interface';
import { UserRole } from '../auth/constants';
import { UpdateUserDto } from './dto/update-user.dto';
import { AuthRepository } from '../auth/auth.repository';
import { ResetPasswordDto } from './dto/reset-password.dto';
import { plainToInstance } from 'class-transformer';
import { User } from './entity/user.entity';

@Injectable()
export class UsersService extends BaseService<UsersModel> {
  constructor(
    private readonly usersRepository: UsersRepository,
    private readonly authRepository: AuthRepository,
  ) {
    super(usersRepository, new UsersModel());
  }

  async createUser(createUserDto: CreateUserDto): Promise<any> {
    const existingUser = await this.authRepository.findUserByEmail(
      createUserDto.email,
    );
    if (existingUser) {
      throw new UnauthorizedException('Email already exists');
    }
    createUserDto.password = await bcrypt.hash(createUserDto.password, 10);
    return this.usersRepository.create(createUserDto);
  }

  async updateUser(updateUserDto: UpdateUserDto): Promise<ResponseUserDto> {
    const user = await this.usersRepository.findById(updateUserDto.id);
    if (!user) {
      throw new NotFoundException('User not found');
    }
    if (updateUserDto.email && updateUserDto.email !== user.email) {
      const emailExists = await this.authRepository.findUserByEmail(
        updateUserDto.email,
      );
      if (emailExists) {
        throw new UnauthorizedException('Email already in use');
      }
    }
    return this.usersRepository.update(updateUserDto.id, updateUserDto);
  }

  async resetpassword(
    resetPasswordDto: ResetPasswordDto,
  ): Promise<ResponseUserDto> {
    const user: User = await this.usersRepository.findById(
      resetPasswordDto.user_id,
    );
    if (!user) {
      throw new NotFoundException('User not found');
    }

    user.password = await bcrypt.hash(resetPasswordDto.password, 10);
    user.updated_at = new Date();

    return this.usersRepository.update(user.id, user);
  }

  async deleteUser(id: number): Promise<any> {
    const user = await this.usersRepository.findById(id);
    if (!user) {
      throw new NotFoundException('User not found');
    }

    const result = await this.usersRepository.deleteUser(id);
    return { deleted: result };
  }

  async findAll(userListDto: UserListDto): Promise<UserListDto> {
    const users = await this.usersRepository.callFunction<any>(
      'get_all_users',
      [userListDto.pageSize, userListDto.startIndex],
    );
    userListDto.result = users[0].get_all_users?.users;
    userListDto.totalRecords = users[0].get_all_users?.total_records || 0;

    return userListDto;
  }
}

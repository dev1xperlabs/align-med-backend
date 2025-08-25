import {
  Controller,
  Get,
  Post,
  Body,
  Patch,
  Param,
  Delete,
  Put,
  UseGuards,
  HttpCode,
  HttpStatus,
  Req,
  HttpException,
} from '@nestjs/common';
import { UsersService } from './users.service';

// import { UpdateRuleDto } from './dto/update-rule.dto';
// import { ResultDto } from '../globalDto/result.dto';
// import { RuleListDto } from './dto/get-all-rules.dto';
import { UserListDto } from './dto/user-list.dto';
import { AuthGuard } from '@nestjs/passport';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';
import { ResetPasswordDto } from './dto/reset-password.dto';
import { ResultDto } from '../globalDto/result.dto';

@Controller('api/v1/users')
export class UsersController {
  constructor(private readonly userService: UsersService) { }

  @Post('get-all-users')
  @UseGuards(AuthGuard('jwt'))
  @HttpCode(HttpStatus.OK)
  async findAll(@Body() userListDto: UserListDto): Promise<UserListDto> {
    return this.userService.findAll(userListDto);
  }

  @Get('get-user/:id')
  @UseGuards(AuthGuard('jwt'))
  @HttpCode(HttpStatus.OK)
  async findById(@Param('id') id: number): Promise<ResultDto> {
    try {
      const user = await this.userService.findById(id);
      return new ResultDto({
        statusCode: '200',
        resultMessage: 'User found successfully',
        result: user,
      });
    } catch (error) {
      return new ResultDto({
        statusCode: '404',
        resultMessage: 'User not found',
        error: error.name,
        errorMessage: error.message,
      });
    }
  }

  @Post('create-user')
  @UseGuards(AuthGuard('jwt'))
  @HttpCode(HttpStatus.CREATED)
  async createUser(@Body() createUserDto: CreateUserDto): Promise<ResultDto> {
    try {
      const user = await this.userService.createUser(createUserDto);
      return new ResultDto({
        statusCode: '201',
        resultMessage: 'User created successfully',
        result: user.id,
      });
    } catch (error) {
      throw new HttpException(
        new ResultDto({
          statusCode: '500',
          resultMessage: 'Failed to create User',
          error: error.name,
          errorMessage: error.message,
        }),
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
  }

  @Put('update-user')
  @UseGuards(AuthGuard('jwt'))
  @HttpCode(HttpStatus.OK)
  async updateUser(@Body() updateUserDto: UpdateUserDto): Promise<ResultDto> {
    try {
      const updateUser = await this.userService.updateUser(updateUserDto);
      return new ResultDto({
        statusCode: '200',
        resultMessage: 'User updated successfully',
        result: updateUser.id,
      });
    } catch (error) {
      throw new HttpException(
        new ResultDto({
          statusCode: '500',
          resultMessage: 'Failed to update User',
          error: error.name,
          errorMessage: error.message,
        }),
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
  }

  @Put('reset-password')
  @UseGuards(AuthGuard('jwt'))
  @HttpCode(HttpStatus.OK)
  async resetPassword(
    @Body() resetPasswordDto: ResetPasswordDto,
  ): Promise<ResultDto> {
    try {
      const resetPassword =
        await this.userService.resetpassword(resetPasswordDto);
      return new ResultDto({
        statusCode: '200',
        resultMessage: 'Passwrod reset successfully',
        result: resetPassword,
      });
    } catch (error) {
      return new ResultDto({
        statusCode: '500',
        resultMessage: 'Failed to reset the password',
        error: error.name,
        errorMessage: error.message,
      });
    }
  }

  @Delete('delete-user/:id')
  @UseGuards(AuthGuard('jwt'))
  @HttpCode(HttpStatus.OK)
  async deleteUser(@Param('id') id: number): Promise<ResultDto> {
    try {
      await this.userService.deleteUser(id);
      return new ResultDto({
        statusCode: '200',
        resultMessage: 'User deleted successfully',
      });
    } catch (error) {
      return new ResultDto({
        statusCode: '500',
        resultMessage: 'Failed to delete user',
        error: error.name,
        errorMessage: error.message,
      });
    }
  }
}

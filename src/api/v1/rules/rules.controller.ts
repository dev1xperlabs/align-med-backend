import { Controller, Get, Post, Body, Patch, Param, Delete, Put, UseGuards, HttpCode, HttpStatus } from '@nestjs/common';
import { RulesService } from './rules.service';
import { CreateRuleDto } from './dto/create-rule.dto';
import { UpdateRuleDto } from './dto/update-rule.dto';
import { ResultDto } from '../globalDto/result.dto';
import { RuleListDto } from './dto/get-all-rules.dto';
import { AuthGuard } from '@nestjs/passport';

@Controller('api/v1/rules')
export class RulesController {
  constructor(private readonly rulesService: RulesService) { }

  @Post("create-rule")
  @UseGuards(AuthGuard('jwt'))
  @HttpCode(HttpStatus.CREATED)
  async create(@Body() createRuleDto: CreateRuleDto): Promise<ResultDto> {
    try {
      const rule = await this.rulesService.createRule(createRuleDto);
      return new ResultDto({
        statusCode: '201',
        resultMessage: 'Rule created successfully',
        result: rule.id,
      });
    } catch (error) {
      return new ResultDto({
        statusCode: '500',
        resultMessage: 'Failed to create rule',
        error: error.name,
        errorMessage: error.message,
      });
    }
  }

  @Get("get-all-rules")
  @UseGuards(AuthGuard('jwt'))
  @HttpCode(HttpStatus.OK)
  async findAll(): Promise<RuleListDto[]> {
    return this.rulesService.findAll();
  }

  @Get('get-rule-by-id/:id')
  @UseGuards(AuthGuard('jwt'))
  @HttpCode(HttpStatus.OK)
  async findOne(@Param('id') id: string): Promise<RuleListDto> {
    return this.rulesService.findRuleById(id)
  }

  @Put('update-rule/:id')
  @UseGuards(AuthGuard('jwt'))
  @HttpCode(HttpStatus.OK)
  async update(@Param('id') id: string, @Body() updateRuleDto: UpdateRuleDto): Promise<ResultDto> {
    try {
      const updatedRule = await this.rulesService.updateRule(id, updateRuleDto);
      return new ResultDto({
        statusCode: '200',
        resultMessage: 'Rule updated successfully',
        result: updatedRule,
      });
    } catch (error) {
      return new ResultDto({
        statusCode: '500',
        resultMessage: 'Failed to update rule',
        error: error.name,
        errorMessage: error.message,
      });
    }
  }

  @Delete('delete-rule/:id')
  @UseGuards(AuthGuard('jwt'))
  @HttpCode(HttpStatus.OK)
  async remove(@Param('id') id: string): Promise<ResultDto> {
    try {
      await this.rulesService.removeRule(id);
      return new ResultDto({
        statusCode: '200',
        resultMessage: 'Rule deleted successfully',
      });
    } catch (error) {
      return new ResultDto({
        statusCode: '500',
        resultMessage: 'Failed to delete rule',
        error: error.name,
        errorMessage: error.message,
      });
    }
  }
}

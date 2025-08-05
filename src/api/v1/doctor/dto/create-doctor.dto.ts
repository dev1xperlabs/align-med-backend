import { IsArray, IsNumber, IsString, IsOptional } from "class-validator"

export class CreateDoctorDto {
  @IsOptional()
  @IsString()
  id?: string

  @IsString()
  rule_name: string

  @IsString()
  doctor_name: string

  @IsNumber()
  bonus_percentage: number

  @IsArray()
  @IsString({ each: true })
  attorneys: string[]
}

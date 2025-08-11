import { NestFactory, Reflector } from '@nestjs/core';
import { AppModule } from './app.module';
import { JwtAuthGuard } from './guards/jwt-auth.guard';
import { ValidationPipe } from '@nestjs/common';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // CORS — adjust to your domains
  app.enableCors({
    origin: ['https://app.alignmedusa.com', 'http://localhost:3000'], // add http://localhost:3000 for local dev
    methods: ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With'],
    credentials: true, // if you use cookies or send Authorization headers
    maxAge: 86400,     // cache preflight for a day
  });

  const reflector = app.get(Reflector);
  app.enableCors({
    origin: '*  ',
    credentials: true,
  })
  app.useGlobalGuards(new JwtAuthGuard(reflector));
  app.useGlobalPipes(new ValidationPipe({ transform: true }));
  await app.listen(process.env.PORT ?? 3001);
  console.log(`Server is running on port ${process.env.PORT ?? 3001}`);
}
bootstrap();



